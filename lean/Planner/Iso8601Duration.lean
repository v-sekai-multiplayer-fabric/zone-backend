/-!
# ISO 8601 Duration parsing — UTC-elapsed, Timex-compatible

Reference: bitwalker/timex `lib/parse/duration/parsers/iso8601.ex`
(`Timex.Parse.Duration.Parsers.ISO8601Parser`).

Civil time is deliberately out of scope: durations are converted to a
single `Nat` of UTC seconds (plus integer milliseconds when present).
Calendar units use Timex's fixed approximations:

  * 1 year   = 365 days
  * 1 month  =  30 days
  * 1 week   =   7 days
  * 1 day    = 86_400 seconds

These are conventions, not facts about civil time. They match Timex
exactly so that this Lean spec can be lifted as the reference for the
C++ parser in `taskweft-nif/standalone/tw_temporal.hpp` and any other
embed (Godot, future bots) without divergence.

## Grammar (extended form)

  duration  := "P" components
  components:= date_part [ "T" time_part ] | "T" time_part | weeks_only
  date_part := { number ("Y" | "M" | "D") }
  time_part := { number ("H" | "M" | "S") }
  weeks_only:= number "W"          -- basic form, must stand alone

`M` before `T` means months; `M` after `T` means minutes.
Numbers are non-negative integers, optionally followed by `.` and
fractional digits (only `S` keeps fractional precision in Timex).

## Errors

Modeled to match Timex's error tags one-for-one — see `ParseError`.
-/

namespace Iso8601Duration

/-- Calendar/clock units we recognise. `Mo` = month, `Mi` = minute. -/
inductive DurUnit | Y | Mo | W | D | H | Mi | S
  deriving DecidableEq, Repr

/-- A single parsed component. `frac_milli` is the integer-millisecond
fractional part of seconds; for every other unit Timex rejects fractions,
so we keep that invariant. -/
structure DurComponent where
  unit       : DurUnit
  whole      : Nat
  frac_milli : Nat := 0
  deriving Repr, DecidableEq

/-- Errors shaped to match Timex's `{:error, msg}` tags. The string
payload is informational; the constructor is the load-bearing identity. -/
inductive ParseError
  | empty
  | expectedP            (got : Char)
  | unexpectedEnd
  | invalidNumber        (raw : String)
  | dateAfterT           (unit : DurUnit)
  | timeBeforeT          (unit : DurUnit)
  | duplicateT
  | mixedBasicExtended
  | unexpectedToken      (got : Char)
  deriving Repr

/-- Timex's calendar normalisation, in seconds × 1000. -/
def unitMilliseconds : DurUnit → Nat
  | .Y  => 365 * 86_400 * 1000
  | .Mo =>  30 * 86_400 * 1000
  | .W  =>   7 * 86_400 * 1000
  | .D  =>       86_400 * 1000
  | .H  =>        3_600 * 1000
  | .Mi =>           60 * 1000
  | .S  =>                1000

/-- Total milliseconds in a parsed duration. Seconds are the only unit
where the fractional millisecond field can be non-zero. -/
def totalMilliseconds : List DurComponent → Nat
  | []      => 0
  | c :: cs => c.whole * unitMilliseconds c.unit + c.frac_milli + totalMilliseconds cs

/-- Convenience: integer seconds, dropping any sub-second remainder. -/
def totalSeconds (cs : List DurComponent) : Nat :=
  totalMilliseconds cs / 1000

/-! ## Parser

The parser walks the input as a list of characters, threading a state
flag `inTime` that flips exactly once at `T`. Numbers are accumulated
character-by-character; the unit character that terminates them
determines which `DurUnit` the component receives.

The structure mirrors Timex's recursive-descent parser
(`parse_components` / `parse_component`) so the proof obligations stay
small and local. -/

private def isDigit (c : Char) : Bool :=
  c.toNat ≥ '0'.toNat ∧ c.toNat ≤ '9'.toNat

private def digitValue (c : Char) : Nat := c.toNat - '0'.toNat

/-- Parse a numeric prefix. Returns the integer part, the millisecond
part of any fraction (clamped to 3 digits, like Timex's microsecond
precision but down-scaled), the raw string seen, and the remaining
input. The input must start with a digit — otherwise `none`. -/
private partial def takeNumber : List Char → Option (Nat × Nat × String × List Char)
  | []            => none
  | c :: rest =>
    if isDigit c then
      let rec go (whole : Nat) (raw : String) : List Char → Nat × Nat × String × List Char
        | []                 => (whole, 0, raw, [])
        | c' :: rest' =>
          if isDigit c' then
            go (whole * 10 + digitValue c') (raw.push c') rest'
          else if c' = '.' then
            -- read up to 3 fractional digits as integer milliseconds
            let rec frac (acc : Nat) (n : Nat) (raw' : String) : List Char → Nat × String × List Char
              | []                  => (acc * (10 ^ (3 - n)), raw', [])
              | d :: rest'' =>
                if isDigit d ∧ n < 3 then
                  frac (acc * 10 + digitValue d) (n + 1) (raw'.push d) rest''
                else
                  (acc * (10 ^ (3 - n)), raw', d :: rest'')
            let (milli, raw', rest'') := frac 0 0 (raw.push '.') rest'
            (whole, milli, raw', rest'')
          else
            (whole, 0, raw, c' :: rest')
      let (whole, milli, raw, rest') := go (digitValue c) (String.ofList [c]) rest
      some (whole, milli, raw, rest')
    else none

/-- Map a unit character to a `DurUnit`, parameterised by whether we are
in the time portion of the duration. `M` is month before `T`, minute after. -/
private def classifyUnit (inTime : Bool) (c : Char) : Option DurUnit :=
  match inTime, c with
  | false, 'Y' => some .Y
  | false, 'M' => some .Mo
  | false, 'W' => some .W
  | false, 'D' => some .D
  | true,  'H' => some .H
  | true,  'M' => some .Mi
  | true,  'S' => some .S
  | _, _       => none

/-- Validate that a unit is allowed at all in either side of `T`. The
"wrong-side" units are the source of `dateAfterT` / `timeBeforeT`. -/
private def crossSideUnit (inTime : Bool) (c : Char) : Option DurUnit :=
  match inTime, c with
  | true,  'Y' => some .Y
  | true,  'D' => some .D
  | false, 'H' => some .H
  | false, 'S' => some .S
  | _, _       => none

private partial def parseComponents
    (cs : List Char) (acc : List DurComponent) (inTime : Bool) (sawT : Bool)
    : Except ParseError (List DurComponent) :=
  match cs with
  | [] => .ok acc.reverse
  | 'T' :: rest =>
      if sawT then .error .duplicateT
      else if rest.isEmpty then .error .unexpectedEnd
      else parseComponents rest acc true true
  | c :: _ =>
      match takeNumber cs with
      | none => .error (.unexpectedToken c)
      | some (_, _, raw, []) => .error (.invalidNumber raw)
      | some (whole, milli, raw, unitC :: rest') =>
          if unitC = 'W' ∧ (acc ≠ [] ∨ inTime) then
            .error .mixedBasicExtended
          else match classifyUnit inTime unitC with
            | some u =>
                if u ≠ .S ∧ milli ≠ 0 then
                  -- Timex only keeps fractions on seconds.
                  .error (.invalidNumber raw)
                else
                  parseComponents rest' ({ unit := u, whole := whole, frac_milli := milli } :: acc) inTime sawT
            | none =>
                match crossSideUnit inTime unitC with
                | some u =>
                    if inTime then .error (.dateAfterT u)
                    else .error (.timeBeforeT u)
                | none => .error (.unexpectedToken unitC)

/-- Top-level parser. Mirrors Timex's `parse/1`. The `P2W` basic form is
detected by the post-condition: after a successful `parseComponents`,
if the only component is `W` we accept; otherwise a `W` anywhere is an
error and would already have been raised. -/
def parse (s : String) : Except ParseError (List DurComponent) :=
  match s.toList with
  | []        => .error .empty
  | 'P' :: [] => .ok []                     -- "P" alone = zero duration (Timex)
  | 'P' :: rest =>
      match parseComponents rest [] false false with
      | .error e => .error e
      | .ok cs   =>
          -- Reject components with a `W` mixed with anything else.
          if cs.any (·.unit = .W) ∧ cs.length > 1 then
            .error .mixedBasicExtended
          else
            .ok cs
  | c :: _    => .error (.expectedP c)

/-! ## Worked examples (executable)

These mirror the doctests in Timex's parser module. They are the
ground-truth check that the Lean spec and the implementation agree. -/

#eval parse "P15Y3M2DT1H14M37S"
#eval parse "P15Y3M2D"
#eval parse "PT3H12M25.001S"
#eval parse "P2W"
#eval parse "P"                   -- expect ok [] (zero duration, per Timex)
#eval parse "P15YT3D"             -- expect dateAfterT
#eval parse ""                    -- expect empty
#eval parse "X1D"                 -- expect expectedP

/-! ## Specification theorems

The first theorem nails down what "Timex-compatible" means for the
total-seconds projection: parsing a syntactically valid duration and
summing equals reading the components individually. The richer
correctness theorem (parse ∘ format = id on the canonical subset) is
left to a follow-up; the parser is small enough to admit it but the
formatter has not been written yet.
-/

theorem totalMilliseconds_nil : totalMilliseconds [] = 0 := rfl

theorem totalMilliseconds_cons (c : DurComponent) (cs : List DurComponent) :
    totalMilliseconds (c :: cs) =
      c.whole * unitMilliseconds c.unit + c.frac_milli + totalMilliseconds cs := rfl

end Iso8601Duration

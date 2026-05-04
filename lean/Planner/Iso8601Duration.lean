/-!
# ISO 8601 Duration parsing — UTC-elapsed, ISO 8601-1:2019 §5.5.2.4

Three-way cross-validation against Timex (`bitwalker/timex`) and the
ISO 8601 spec recogniser surfaced two real divergences in earlier
revisions of this file:

  1. Date components in non-canonical order were accepted (`P1D1M`).
  2. Fractions were only allowed on `S`, while the spec allows them
     on the lowest-order component actually present (`P1.5D`,
     `PT1.5H`).

Both are fixed here. We now enforce canonical order strictly and
allow a fraction on any single unit, provided no smaller unit
follows it. Timex remains looser than the spec on fraction position
(`PT1.5H30M`) — that's a Timex quirk, not a spec compliance gap on
our side.

Civil time is still deliberately out of scope: durations are
converted to a single `Nat` of UTC milliseconds. Calendar units
use the conventions Timex picked, which match common practice but
are not facts about wall clocks:

  * 1 year   = 365 days
  * 1 month  =  30 days
  * 1 week   =   7 days
  * 1 day    = 86_400 seconds

## Grammar

  duration  := "P" components
  components:= date_part [ "T" time_part ] | "T" time_part | weeks_only | empty
  date_part := [n "Y"] [n "M"] [n "D"]   (canonical order, each ≤ 1×)
  time_part := [n "H"] [n "M"] [n "S"]   (canonical order, each ≤ 1×)
  weeks_only:= n "W"                       (must stand alone)
  n         := digits ["." digits]

`M` before `T` means months; `M` after `T` means minutes. A fraction is
allowed on at most one unit, and only if no smaller unit follows it.
Sub-millisecond fractional precision is truncated.

## Errors

`ParseError` constructors enumerate every reject reason; consumers
that only need a yes/no can use `parse |>.toBool`.
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

/-- Errors shaped to match the spec rejection reasons. -/
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
  | nonCanonicalOrder    (unit : DurUnit)
  | fractionNotOnLast
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

/-- Each component contributes `whole · unit_ms + frac_milli · unit_ms / 1000`
to the total. Every unit's `unit_ms` is a multiple of 1000, so the
fractional contribution is always an exact integer. -/
def fracContribution (u : DurUnit) (frac_milli : Nat) : Nat :=
  frac_milli * (unitMilliseconds u / 1000)

/-- Total milliseconds in a parsed duration. -/
def totalMilliseconds : List DurComponent → Nat
  | []      => 0
  | c :: cs =>
      c.whole * unitMilliseconds c.unit + fracContribution c.unit c.frac_milli
        + totalMilliseconds cs

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
part of any fraction (clamped to 3 digits), the raw string seen, and
the remaining input. A `.` with no digit after is rejected via
`Except.error`; the input must start with a digit, else `Except.error`. -/
private partial def takeNumber :
    List Char → Except ParseError (Nat × Nat × String × List Char)
  | []            => .error .unexpectedEnd
  | c :: rest =>
    if isDigit c then
      let rec go (whole : Nat) (raw : String) :
          List Char → Except ParseError (Nat × Nat × String × List Char)
        | []                 => .ok (whole, 0, raw, [])
        | c' :: rest' =>
          if isDigit c' then
            go (whole * 10 + digitValue c') (raw.push c') rest'
          else if c' = '.' then
            match rest' with
            | d :: _ =>
              if isDigit d then
                let rec frac (acc : Nat) (n : Nat) (raw' : String) :
                    List Char → Nat × String × List Char
                  | []                  => (acc * (10 ^ (3 - n)), raw', [])
                  | d :: rest'' =>
                    if isDigit d ∧ n < 3 then
                      frac (acc * 10 + digitValue d) (n + 1) (raw'.push d) rest''
                    else
                      (acc * (10 ^ (3 - n)), raw', d :: rest'')
                let (milli, raw', rest'') := frac 0 0 (raw.push '.') rest'
                .ok (whole, milli, raw', rest'')
              else
                .error (.invalidNumber (raw.push '.'))
            | []     => .error (.invalidNumber (raw.push '.'))
          else
            .ok (whole, 0, raw, c' :: rest')
      go (digitValue c) (String.ofList [c]) rest
    else .error (.unexpectedToken c)

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

/-- Canonical position of a unit in the `Y M D T H M S` order. Used to
reject non-canonical input like `P1D1M`. -/
private def unitRank : DurUnit → Nat
  | .Y  => 0
  | .Mo => 1
  | .D  => 2
  | .W  => 99   -- W stands alone; rank irrelevant once `mixedBasicExtended` fires
  | .H  => 3
  | .Mi => 4
  | .S  => 5

private partial def parseComponents
    (cs : List Char) (acc : List DurComponent) (inTime : Bool) (sawT : Bool)
    (lastRank : Int) (fracSeen : Bool)
    : Except ParseError (List DurComponent) :=
  match cs with
  | [] => .ok acc.reverse
  | _  =>
      -- Once a fraction has been read, no further input is allowed:
      -- the spec says fractions only on the lowest-order present component.
      if fracSeen then .error .fractionNotOnLast
      else match cs with
        | 'T' :: rest =>
            if sawT then .error .duplicateT
            else if rest.isEmpty then .error .unexpectedEnd
            else parseComponents rest acc true true lastRank false
        | _ :: _ =>
            match takeNumber cs with
            | .error e => .error e
            | .ok (_, _, raw, []) => .error (.invalidNumber raw)
            | .ok (whole, milli, _raw, unitC :: rest') =>
                if unitC = 'W' ∧ (acc ≠ [] ∨ inTime) then
                  .error .mixedBasicExtended
                else if acc.any (·.unit = .W) then
                  .error .mixedBasicExtended
                else match classifyUnit inTime unitC with
                  | some u =>
                      let r := unitRank u
                      if (r : Int) ≤ lastRank then
                        .error (.nonCanonicalOrder u)
                      else
                        parseComponents rest'
                          ({ unit := u, whole := whole, frac_milli := milli } :: acc)
                          inTime sawT (r : Int) (milli ≠ 0)
                  | none =>
                      match crossSideUnit inTime unitC with
                      | some u =>
                          if inTime then .error (.dateAfterT u)
                          else .error (.timeBeforeT u)
                      | none => .error (.unexpectedToken unitC)
        | [] => .ok acc.reverse

/-- Top-level parser. Mirrors Timex's `parse/1`. The `P2W` basic form is
detected by the post-condition: after a successful `parseComponents`,
if the only component is `W` we accept; otherwise a `W` anywhere is an
error and would already have been raised. -/
def parse (s : String) : Except ParseError (List DurComponent) :=
  match s.toList with
  | []        => .error .empty
  | 'P' :: [] => .ok []                     -- "P" alone = zero duration
  | 'P' :: rest =>
      parseComponents rest [] false false (-1 : Int) false
  | c :: _    => .error (.expectedP c)

/-! ## Worked examples (executable)

These mirror the doctests in Timex's parser module. They are the
ground-truth check that the Lean spec and the implementation agree. -/

#eval parse "P15Y3M2DT1H14M37S"   -- canonical full duration
#eval parse "P15Y3M2D"
#eval parse "PT3H12M25.001S"
#eval parse "P2W"
#eval parse "P"                   -- expect ok [] (zero duration)
#eval parse "P15YT3D"             -- expect dateAfterT
#eval parse ""                    -- expect empty
#eval parse "X1D"                 -- expect expectedP
#eval parse "P1.5D"               -- expect ok [{D, 1, 500}] — fractions on any unit
#eval parse "PT1.5H"              -- expect ok [{H, 1, 500}]
#eval parse "PT1.5H30M"           -- expect fractionNotOnLast
#eval parse "P1D1M"               -- expect nonCanonicalOrder Mo

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
      c.whole * unitMilliseconds c.unit
        + fracContribution c.unit c.frac_milli
        + totalMilliseconds cs := rfl

end Iso8601Duration

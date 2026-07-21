; SPDX-License-Identifier: MIT
; Copyright (c) 2026 K. S. Ernest (iFire) Lee
;
; HTN planner, ported from standalone/tw_planner.hpp (tw_seek_plan) and
; the runtime behavior of standalone/tw_loader.hpp's action/method
; builders and expression evaluator (RFD 0023, Stage 5A). Unlike the
; earlier design note, this is NOT split between "search in the guest,
; domain evaluation on the host" -- everything runs here, in compiled
; Scheme. The only host round trip is `hash-table-set` (RFD 0021's
; existing generic map-handle ops, plus one addition: Elixir maps are
; immutable, so a functional "insert" must cross the boundary the same
; way `hash-table-ref` already does for reads). state/actions/methods/
; tasks/nodes are ordinary host-owned List/Map/Atom/fixnum/bool handles
; the guest walks with car/cdr/list-ref/hash-table-ref, same convention
; as rebac.scm's edge lists.
;
; Explicitly out of scope for Stage 5A (see RFD 0023): the full
; KHR_interactivity float/trig/quaternion/matrix node vocabulary (no
; float support anywhere in this compiler -- state/desired/literal
; values are fixnums, booleans, or atoms only for now), scan methods,
; ReBAC-based goal bindings, replan/solution-tree/temporal (all
; unreachable from Uro.Ports.Planner.plan/1 anyway).
;
; --- Wire shapes (all host-owned, built once per plan() call by
;     Uro.Planner.SandboxAdapter, which does nothing but translate
;     parsed JSON into these tagged lists -- no domain logic lives
;     there) ---
;
;   task    = ("call" name args) | ("goal" bindings) | ("multigoal" bindings)
;   binding = (var key desired)
;   action  = (params binds body)          body  = list of step
;   method  = (params binds checks subtasks)
;   step    = ("eval" node) | ("set" var key node)
;   subtask-def = (name arg-nodes)
;   node    = ("lit" value) | ("param" name) | ("get" var key)
;           | ("eq" a b) | ("lt" a b) | ("add" a b) | ("sub" a b)
;           | ("not" a) | ("and" a b) | ("or" a b)
;
; `tags`: a 15-element list of ATOMS (interned by Program's boxing, so
; guest eq? works on them) carrying every structural tag above, in a
; fixed order -- like rebac.scm's rel-consts, the reader has no string
; (or bare symbol) literals, so even these fixed constants are
; caller-supplied: (call goal multigoal eval set lit param get eq lt
; add sub not and or). `ctx` bundles (actions-tbl methods-tbl tags).
;
; Search semantics kept, matching tw_seek_plan exactly (splice order and
; fuel placement checked against RFD 0023's analysis):
;   - TwGoal: subtasks ++ (goal) ++ remaining -- goal re-verifies before
;     `remaining` runs.
;   - TwMultiGoal: try EVERY unmet binding as the next thing to satisfy.
;   - Compound TwCall: subtasks ++ remaining, no self-re-append.
;   - Fuel spent ONLY on real branching (goal/multigoal/compound-task
;     decisions), never on primitive-action or satisfied-goal advance --
;     mirrors tw_seek_plan's fast path (TW_MAX_DEPTH bounds branching
;     depth, not sequence length).
; Dropped on purpose (pure performance in the original -- see RFD 0023):
; fail/success-cache memoization, method-ordering statistics (a fresh
; call starts these at zero anyway), decomposition dedup, the
; witness-oracle prefix pruning, the wall-clock budget (guest fuel is
; an equivalent structural DoS guard).
;
; One deliberate Stage-5A simplification vs. native: an action/check
; "eval" step here uses ordinary Scheme truthiness (only #f fails) where
; tw_loader.hpp additionally requires the result be *literally* a
; boolean (a non-boolean result also fails natively). Every hand-built
; Stage-5A test domain's eval nodes are boolean-valued by construction,
; so this never diverges in practice; documented rather than silently
; assumed.

(define (ctx-actions ctx) (car ctx))
(define (ctx-methods ctx) (car (cdr ctx)))
(define (ctx-tags ctx) (car (cdr (cdr ctx))))

(define (tag-call tags) (list-ref tags 0))
(define (tag-goal tags) (list-ref tags 1))
(define (tag-multigoal tags) (list-ref tags 2))
(define (tag-eval tags) (list-ref tags 3))
(define (tag-set tags) (list-ref tags 4))
(define (tag-lit tags) (list-ref tags 5))
(define (tag-param tags) (list-ref tags 6))
(define (tag-get tags) (list-ref tags 7))
(define (tag-eq tags) (list-ref tags 8))
(define (tag-lt tags) (list-ref tags 9))
(define (tag-add tags) (list-ref tags 10))
(define (tag-sub tags) (list-ref tags 11))
(define (tag-not tags) (list-ref tags 12))
(define (tag-and tags) (list-ref tags 13))
(define (tag-or tags) (list-ref tags 14))

(define (append a b)
  (if (null? a) b (cons (car a) (append (cdr a) b))))

; --- Task/binding accessors ---

(define (task-tag t) (car t))
(define (task-call-name t) (car (cdr t)))
(define (task-call-args t) (car (cdr (cdr t))))
(define (task-bindings t) (car (cdr t)))

(define (binding-var b) (car b))
(define (binding-key b) (car (cdr b)))
(define (binding-desired b) (car (cdr (cdr b))))

; --- State: a 2-level host-owned map, var -> (key -> value). Reading a
;     var/key that was never set returns #f (matches hash-table-ref's
;     own "missing key -> #f"); writing one that doesn't exist yet
;     creates it (hash-table-set treats a #f "map" as empty). ---

(define (nested-ref state var key)
  (let ((inner (hash-table-ref state var)))
    (if inner (hash-table-ref inner key) #f)))

(define (nested-set state var key value)
  (hash-table-set state var (hash-table-set (hash-table-ref state var) key value)))

(define (goal-satisfied? state var key desired)
  (eq? (nested-ref state var key) desired))

(define (binding-satisfied? state b)
  (goal-satisfied? state (binding-var b) (binding-key b) (binding-desired b)))

(define (goal-satisfied-all? state bindings)
  (if (null? bindings)
    #t
    (if (binding-satisfied? state (car bindings))
      (goal-satisfied-all? state (cdr bindings))
      #f)))

; First unmet binding, or #f if every binding is satisfied.
(define (first-unmet state bindings)
  (if (null? bindings)
    #f
    (if (binding-satisfied? state (car bindings))
      (first-unmet state (cdr bindings))
      (car bindings))))

; Every unmet binding, as a list (multigoal backtracks over all of them).
(define (all-unmet state bindings)
  (if (null? bindings)
    (list)
    (if (binding-satisfied? state (car bindings))
      (all-unmet state (cdr bindings))
      (cons (car bindings) (all-unmet state (cdr bindings))))))

; --- params: a runtime binding of name -> value, as an alist (list of
;     2-element (name value) lists); small enough that a linear scan
;     compared via atom eq? is simpler than a second host-owned map. ---

(define (params-ref params name)
  (if (null? params)
    #f
    (if (eq? (car (car params)) name)
      (car (cdr (car params)))
      (params-ref (cdr params) name))))

(define (build-params names args)
  (if (null? names)
    (list)
    (if (null? args)
      (list)
      (cons (list (car names) (car args)) (build-params (cdr names) (cdr args))))))

(define (bind-name b) (car b))
(define (bind-var b) (car (cdr b)))
(define (bind-key b) (car (cdr (cdr b))))

(define (run-binds binds params state)
  (if (null? binds)
    params
    (run-binds (cdr binds)
      (cons (list (bind-name (car binds))
          (nested-ref state (bind-var (car binds)) (bind-key (car binds))))
        params)
      state)))

; --- Expression evaluator: the KHR_interactivity-style node language,
;     restricted to what this stage needs (arithmetic/comparison/state
;     access -- no floats, no trig/quaternion/matrix). ---

(define (node-tag n) (car n))
(define (node-a n) (car (cdr n)))
(define (node-b n) (car (cdr (cdr n))))

(define (eval-node node params state tags)
  (if (eq? (node-tag node) (tag-lit tags))
    (node-a node)
    (if (eq? (node-tag node) (tag-param tags))
      (params-ref params (node-a node))
      (if (eq? (node-tag node) (tag-get tags))
        (nested-ref state (node-a node) (node-b node))
        (if (eq? (node-tag node) (tag-eq tags))
          (eq? (eval-node (node-a node) params state tags)
            (eval-node (node-b node) params state tags))
          (if (eq? (node-tag node) (tag-lt tags))
            (< (eval-node (node-a node) params state tags)
              (eval-node (node-b node) params state tags))
            (if (eq? (node-tag node) (tag-add tags))
              (+ (eval-node (node-a node) params state tags)
                (eval-node (node-b node) params state tags))
              (if (eq? (node-tag node) (tag-sub tags))
                (- (eval-node (node-a node) params state tags)
                  (eval-node (node-b node) params state tags))
                (if (eq? (node-tag node) (tag-not tags))
                  (not (eval-node (node-a node) params state tags))
                  (if (eq? (node-tag node) (tag-and tags))
                    (if (eval-node (node-a node) params state tags)
                      (eval-node (node-b node) params state tags)
                      #f)
                    (if (eval-node (node-a node) params state tags)
                      #t
                      (eval-node (node-b node) params state tags))))))))))))

(define (eval-node-list nodes params state tags)
  (if (null? nodes)
    (list)
    (cons (eval-node (car nodes) params state tags)
      (eval-node-list (cdr nodes) params state tags))))

; --- Actions: (params binds body) -> apply-action returns a new state,
;     or #f if a body "eval" step fails. ---

(define (action-params a) (car a))
(define (action-binds a) (car (cdr a)))
(define (action-body a) (car (cdr (cdr a))))

(define (step-tag s) (car s))
(define (step-eval-node s) (car (cdr s)))
(define (step-set-var s) (car (cdr s)))
(define (step-set-key s) (car (cdr (cdr s))))
(define (step-set-node s) (car (cdr (cdr (cdr s)))))

(define (run-body steps params state tags)
  (if (null? steps)
    state
    (let ((step (car steps)))
      (if (eq? (step-tag step) (tag-eval tags))
        (if (eval-node (step-eval-node step) params state tags)
          (run-body (cdr steps) params state tags)
          #f)
        (run-body (cdr steps) params
          (nested-set state (step-set-var step) (step-set-key step)
            (eval-node (step-set-node step) params state tags))
          tags)))))

(define (apply-action action state args tags)
  (let ((params (build-params (action-params action) args)))
    (run-body (action-body action) (run-binds (action-binds action) params state) state tags)))

; --- Methods: (params binds checks subtasks) -> try-method returns a
;     (possibly empty) subtask-list, or #f if a check clause fails. ---

(define (method-params m) (car m))
(define (method-binds m) (car (cdr m)))
(define (method-checks m) (car (cdr (cdr m))))
(define (method-subtasks m) (car (cdr (cdr (cdr m)))))

(define (run-checks checks params state tags)
  (if (null? checks)
    #t
    (if (eval-node (car checks) params state tags)
      (run-checks (cdr checks) params state tags)
      #f)))

(define (subtask-name s) (car s))
(define (subtask-arg-nodes s) (car (cdr s)))

(define (build-subtask s params state tags)
  (list (tag-call tags) (subtask-name s) (eval-node-list (subtask-arg-nodes s) params state tags)))

(define (build-subtasks defs params state tags)
  (if (null? defs)
    (list)
    (cons (build-subtask (car defs) params state tags)
      (build-subtasks (cdr defs) params state tags))))

(define (try-method method state args tags)
  (let ((params (run-binds (method-binds method) (build-params (method-params method) args)
          state)))
    (if (run-checks (method-checks method) params state tags)
      (build-subtasks (method-subtasks method) params state tags)
      #f)))

; --- The walker: advances through satisfied goals/primitive actions
;     without spending fuel, recursing into a fuel-spending branch
;     function only once a real decision is needed. Returns a plan
;     (host-owned list of executed ("call" name args) tasks) or #f.
;     Note: nil (the empty plan) is a legitimate SUCCESS, not falsy --
;     Scheme truthiness treats everything except #f as true, so `(if
;     result ...)` below correctly distinguishes "found the empty plan"
;     from "failed". ---

(define (walk-tasks state tasks fuel ctx)
  (if (null? tasks)
    (list)
    (let ((task (car tasks)))
      (if (eq? (task-tag task) (tag-goal (ctx-tags ctx)))
        (if (goal-satisfied-all? state (task-bindings task))
          (walk-tasks state (cdr tasks) fuel ctx)
          (branch-goal state tasks fuel ctx))
        (if (eq? (task-tag task) (tag-multigoal (ctx-tags ctx)))
          (if (goal-satisfied-all? state (task-bindings task))
            (walk-tasks state (cdr tasks) fuel ctx)
            (branch-multigoal state tasks fuel ctx))
          (walk-call state tasks fuel ctx))))))

(define (walk-call state tasks fuel ctx)
  (let ((task (car tasks)))
    (let ((action (hash-table-ref (ctx-actions ctx) (task-call-name task))))
      (if action
        (let ((new-state (apply-action action state (task-call-args task) (ctx-tags ctx))))
          (if new-state
            (let ((rest (walk-tasks new-state (cdr tasks) fuel ctx)))
              (if rest (cons task rest) #f))
            #f))
        (branch-compound state tasks fuel ctx)))))

; --- Branching: unmet TwGoal -- pick the first unmet binding, try each
;     method alternative registered under its var name, in order. ---

(define (branch-goal state tasks fuel ctx)
  (if (< fuel 1)
    #f
    (let ((goal (car tasks)))
      (let ((remaining (cdr tasks)))
        (let ((unmet (first-unmet state (task-bindings goal))))
          (if unmet
            (let ((methods (hash-table-ref (ctx-methods ctx) (binding-var unmet))))
              (if methods
                (let ((args (list (binding-key unmet) (binding-desired unmet))))
                  (try-goal-methods state methods args goal remaining (- fuel 1) ctx))
                #f))
            #f))))))

(define (try-goal-methods state methods args goal remaining fuel ctx)
  (if (null? methods)
    #f
    (let ((subtasks (try-method (car methods) state args (ctx-tags ctx))))
      (if subtasks
        (let ((new-tasks (append subtasks (cons goal remaining))))
          (let ((result (walk-tasks state new-tasks fuel ctx)))
            (if result
              result
              (try-goal-methods state (cdr methods) args goal remaining fuel ctx))))
        (try-goal-methods state (cdr methods) args goal remaining fuel ctx)))))

; --- Branching: TwMultiGoal -- try EVERY unmet binding as the next
;     thing to satisfy (real backtracking over binding choice). ---

(define (branch-multigoal state tasks fuel ctx)
  (if (< fuel 1)
    #f
    (let ((mg (car tasks)))
      (let ((remaining (cdr tasks)))
        (let ((unmet-list (all-unmet state (task-bindings mg))))
          (try-multigoal-bindings state unmet-list mg remaining (- fuel 1) ctx))))))

(define (try-multigoal-bindings state unmet-list mg remaining fuel ctx)
  (if (null? unmet-list)
    #f
    (let ((sub-goal (list (tag-goal (ctx-tags ctx)) (list (car unmet-list)))))
      (let ((new-tasks (cons sub-goal (cons mg remaining))))
        (let ((result (walk-tasks state new-tasks fuel ctx)))
          (if result
            result
            (try-multigoal-bindings state (cdr unmet-list) mg remaining fuel ctx)))))))

; --- Branching: compound TwCall -- try each method alternative in
;     order. No self-re-append (unlike the goal case). ---

(define (branch-compound state tasks fuel ctx)
  (if (< fuel 1)
    #f
    (let ((task (car tasks)))
      (let ((remaining (cdr tasks)))
        (let ((methods (hash-table-ref (ctx-methods ctx) (task-call-name task))))
          (if methods
            (try-compound-methods state methods (task-call-args task) remaining
              (- fuel 1) ctx)
            #f))))))

(define (try-compound-methods state methods args remaining fuel ctx)
  (if (null? methods)
    #f
    (let ((subtasks (try-method (car methods) state args (ctx-tags ctx))))
      (if subtasks
        (let ((new-tasks (append subtasks remaining)))
          (let ((result (walk-tasks state new-tasks fuel ctx)))
            (if result
              result
              (try-compound-methods state (cdr methods) args remaining fuel ctx))))
        (try-compound-methods state (cdr methods) args remaining fuel ctx)))))

; Entry point: 400-fuel bound, matching tw_planner.hpp's TW_MAX_DEPTH.
(define (plan state tasks ctx) (walk-tasks state tasks 400 ctx))

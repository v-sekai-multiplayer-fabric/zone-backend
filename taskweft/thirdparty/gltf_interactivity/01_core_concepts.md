# Concepts

## Graphs

A behavior graph is a JSON object containing *interactivity nodes*. It
**MAY** also contain custom variables and custom events.

Behavior graphs are directed graphs with no directed cycles.

When a glTF asset contains a behavior graph, all glTF animations are
assumed to be controlled by the graph so they **MUST NOT** play
automatically.

## Interactivity Nodes

An *interactivity node* is a JSON object, which represents an executable
item. Each node is defined by its *declaration*, which includes an
*operation* and a (possibly empty) set of *value sockets*. Operations
follow `domain/operation` naming pattern. Depending on the operation, a
node **MAY** have input and/or output *flow sockets*; they **MAY** be
affected by the node’s *configuration*.

### Operation

An *operation* defines a specific set of steps performed by the
execution environment when the interactivity node is executed.

An interactivity node is executed when one of its input flow sockets is
activated, when one of its output value sockets is accessed by another
interactivity node, or when an operation-specific event occurs. An
interactivity node **MAY** repeatedly activate its own input flow
sockets during the execution.

Usually, the interactivity node execution includes evaluating its input
value sockets (if any), processing its own logic, and activating any
number (including zero) of output flow sockets.

Operations **MAY** define internal state. That state is allocated and
maintained per the node using the operation.

Operations **MAY** define internal graph state. That state is allocated
and maintained per the behavior graph containing a node using the
operation.

### Sockets

There are four kinds of sockets.

*Output value sockets* represent data initialized by the interactivity
node’s operation or produced during its execution. For example, it could
be results of math operations or explicitly exposed parts of the
interactivity node’s internal state. Accessing these sockets either
triggers computing the return value on the fly by executing the
operation or returns a value based on the interactivity node’s internal
state. Exact behavior depends on the operation. As a general rule,
output value sockets **MUST** retain their values until an interactivity
node with one or more flow sockets is executed.

> [!NOTE]
> At the current state of the Specification, the retention of output
> value socket values is observable only with the `math/random`
> operation.

*Input value sockets* represent data accessed during the interactivity
node’s execution. For example, it could be arguments of math operations
or execution parameters such as iteration count for loop operations or
duration for time-related operations. Each of these sockets **MUST**
either be given an inline constant value in the interactivity node JSON
object or connected to an output value socket of a different
interactivity node. The operation **MAY** access interactivity node’s
input value sockets multiple times during the execution. The runtime
**MUST** guarantee that all input value sockets have defined values when
the interactivity node’s execution starts.

*Output flow sockets* represent “function pointers” that the
interactivity node will call to advance the graph execution. For
example, bodies and branches of flow control operations are output flow
sockets that drive further execution when certain conditions are
fulfilled. An output flow socket is either connected to exactly one
input flow socket of another interactivity node or unconnected; in the
latter case activating the output flow socket is a no-op.

*Input flow sockets* represent “methods” that could be called on the
interactivity node. For example, flow control operations (such as loops
and branches) usually have an `in` input flow socket that starts their
execution. Additional input flow sockets **MAY** exist such as `reset`
for operations having an internal state. An input flow socket is either
connected to one or more output flow sockets of other interactivity
nodes or unconnected; in the latter case the operation’s “method”
represented by the socket is never called.

Input and output value sockets have associated data types, e.g., floats,
integers, booleans, etc.

Socket ids exist in four separate scopes corresponding to the four
socket kinds.

> [!NOTE]
> For example, an interactivity node with the `flow/sequence` operation
> can have an output flow socket with id `"in"` despite having an input
> flow socket with the same id.

#### Socket Order

Although sockets are inherently unordered within an interactivity node
(because JSON properties are unordered), some operations such as
`flow/sequence` or `flow/multiGate` need a specific socket order to
guarantee predictable behavior. In such cases, the sockets are
implicitly sorted by their ids in ascending order.

For any given ids `a` and `b`, the following procedure **MUST** be used
to determine if `a` is less than `b`.

1.  Let *unitsA* and *unitsB* be the sequences of UTF-16 code units
    corresponding to the socket ids `a` and `b` respectively and
    *lengthA* and *lengthB* be the lengths of these sequences.

2.  Let *minLength* be the minimum of *lengthA* and *lengthB*.

3.  For each integer *i* such that 0 ≤ *i* \< *minLength*, in ascending
    order, do

    1.  if *unitsA\[i\]* \< *unitsB\[i\]* return true;

    2.  if *unitsA\[i\]* \> *unitsB\[i\]* return false.

4.  If *lengthA* \< *lengthB* return true.

5.  Return false.

> [!TIP]
> This is implementable in ECMAScript as follows, assuming that `flows`
> is a JSON object representing output flow sockets:
>
> ``` js
> const sortedSocketIds = Object.keys(flows).sort();
> ```

> [!CAUTION]
> This process enforces lexicographic order solely based on UTF-16 code
> units. In particular, the following two caveats apply:
>
> - A socket id `10` is *less* than a socket id `9`. This could be
>   avoided by padding socket ids to the same number of characters,
>   i.e., using `09` instead of `9` in this case.
>
> - The sorting algorithm does not account for characters that use more
>   than one code unit in UTF-16 encoding. For example, the “North East
>   Sans-Serif Arrow” character has a code point of `0x1F855` encoded as
>   two surrogate code units `[0xD83E, 0xDC55]` so it is *less* than the
>   “Replacement Character” character that has a code point of `0xFFFD`
>   encoded directly as a single code unit.

#### Value Socket Types

All value sockets are strictly typed.

Implementations of this extension **MUST** support the following type
signatures.

bool  
a boolean value

float  
a double precision [IEEE-754](#ieee-754) floating-point scalar value

float2  
a two-component vector of **float** values

float3  
a three-component vector of **float** values

float4  
a four-component vector of **float** values

float2x2  
a 2x2 matrix of **float** values

float3x3  
a 3x3 matrix of **float** values

float4x4  
a 4x4 matrix of **float** values

int  
a two’s complement 32-bit signed integer scalar value

ref  
an opaque reference value

### Configuration

Operations **MAY** be configurable through inline properties
collectively called *configuration* that **MAY** affect the
interactivity node’s behavior and the number of its sockets, such as the
set of cases for the `flow/switch` operation.

If an operation specification does not include any configuration, the
operation is not configurable and any configuration properties defined
for interactivity nodes using the operation in the behavior graph
**MUST** be ignored.

Unless specified otherwise, all configurable operations have a *default*
configuration. The default configuration **MUST** be used when the
behavior graph does not provide any configuration or when the provided
configuration is invalid. If an operation does not have a default
configuration (like `variable/*` operations) and the behavior graph does
not provide a valid configuration, the whole graph is invalid and
**MUST** be rejected.

For a configuration to be valid, all configuration properties defined by
the operation specification **MUST** be provided in the behavior graph
with valid types and values. If any of the configuration properties
defined by the operation specification is omitted or has invalid type or
invalid value, the whole configuration is invalid and the operation
behavior **MUST** fall back to the default configuration if the latter
is supported. Configuration properties present in the behavior graph but
not defined by the operation specification **MUST** be ignored.

Implementations **SHOULD** generate appropriate warnings as deemed
possible when:

- a non-configurable operation has a configuration in the behavior
  graph;

- a provided configuration contains unknown properties;

- a provided configuration is invalid.

#### Configuration Types

Configuration properties use a separate type system unrelated to the
value socket types.

bool  
a boolean value

int  
a two’s complement 32-bit signed integer scalar value

int\[\]  
an array of **int** values

string  
a string value

### Unsupported Operations

If the execution environment does not support the operation, e.g., when
the operation is defined by an unsupported or disabled extension for the
Interactivity Specification, the operation is implicitly replaced with a
“no-op” operation defined as follows:

- activating the interactivity node’s input flow sockets is ignored;

- the interactivity node’s output flow sockets are never activated;

- the interactivity node’s output value sockets have constant
  [type-default](#variables-types) values.

## Custom Events

A behavior graph **MAY** define custom events for interacting with
external execution environments and/or creating asynchronous loops.

A custom event definition includes its value sockets with types and
optional initial values as well as an optional unique string identifier
for linking the event with the external environment.

Semantics of custom events are application-specific.

## Custom Variables

A behavior graph **MAY** define custom variables. A variable **MAY** be
declared simultaneously with its initial value, otherwise the variable
**MUST** be initialized to the type-specific default.

Custom variables **MUST** retain their values until the graph execution
is terminated.

### Custom Variable Types

Custom variables use the same type system as the value sockets. The
following table defines type-default values.

| Type       | Default value               |
|------------|-----------------------------|
| `bool`     | Boolean false               |
| `float`    | Floating-point NaN          |
| `float2`   | Two floating-point NaNs     |
| `float3`   | Three floating-point NaNs   |
| `float4`   | Four floating-point NaNs    |
| `float2x2` | Four floating-point NaNs    |
| `float3x3` | Nine floating-point NaNs    |
| `float4x4` | Sixteen floating-point NaNs |
| `int`      | Integer zero                |
| `ref`      | Null reference              |

## Implementation-Specific Limits

### Static Limits

Implementations **MAY** restrict the size and complexity of behavior
graphs by imposing certain limits on the following statically-known
properties:

- The number of types

- The number of variables

- The number of custom events and the number of value sockets within a
  custom event

- The number of operation declarations

- The number of input and output value sockets in operation declarations

- The number of interactivity nodes

- The number of graph-defined output flow sockets in operations like
  `flow/multiGate` or `flow/sequence`

- The number of configuration-defined output flow sockets in operations
  like `flow/switch`

- The number of configuration-defined input value sockets in operations
  like `pointer/get`, `math/switch`, or `variable/set`

The graph **MUST** be rejected if it exceeds implementation-defined max
values for these properties.

### Dynamic Limits

Implementations **MAY** restrict the runtime capabilities of behavior
graphs by imposing certain limits on the following features that require
dynamic allocation of memory and/or processing power:

- Numbers of simultaneous delays, animations, and interpolations;
  exceeding these limits results in runtime errors that can be
  gracefully handled by the graph itself, see `err` output flows of the
  corresponding operations.

- Number of events processed within a single rendered frame; exceeding
  this limit **MAY** result in an implementation-specific behavior such
  as reducing the frame rate or rescheduling the extra events.

These limits are exposed to behavior graphs via additional glTF Object
Model pointers.


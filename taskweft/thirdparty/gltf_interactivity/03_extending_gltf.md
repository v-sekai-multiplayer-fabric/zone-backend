## Extending glTF Object Model

This Specification defines additional glTF Object Model pointers for use
with `pointer/*` operations.

### Implementation-Specific Runtime Limits

The `maxActiveAnimations` read-only property represents the
implementation-dependent maximum number of simultaneously active
animations for the purpose of the `animation/start` operation.

The `maxActiveDelays` read-only property represents the
implementation-dependent maximum number of simultaneously scheduled
delays for the purpose of the `flow/setDelay` operation.

The `maxActivePropertyInterpolations` read-only property represents the
implementation-dependent maximum number of simultaneously active
property interpolations for the purpose of the `pointer/interpolate`
operation.

The `maxActiveVariableInterpolations` read-only property represents the
implementation-dependent maximum number of simultaneously active
variable interpolations for the purpose of the `variable/interpolate`
operation.

Values of all these properties **MUST** be at least 1.

An implementation **MAY** set any of these properties to 2147483647 (max
possible value for the `int` type) if it does not have an explicit limit
for the corresponding value or decides to not disclose it.

The following pointers represent the read-only properties defined in
this section.

| Pointer | Type |
|----|----|
| `/extensions/KHR_interactivity/limits/maxActiveAnimations` | `int` |
| `/extensions/KHR_interactivity/limits/maxActiveDelays` | `int` |
| `/extensions/KHR_interactivity/limits/maxActivePropertyInterpolations` | `int` |
| `/extensions/KHR_interactivity/limits/maxActiveVariableInterpolations` | `int` |

### Active Camera State

In some viewers, such as, but not limited to, augmented reality viewers
and virtual reality viewers, the viewer implementation gives the user
direct control over a virtual camera. This virtual camera **MAY** be
controlled by user head movements, by movements of the user’s phone with
their hands, or by mouse, keyboard or touch input on a laptop, or by
other means. It is useful for interactivity to be able to react to the
position of this virtual camera.

This Specification defines the “active camera” as the camera
transformation that ought to be reacted to by interactivity. When there
is only one camera being displayed to the user, the implementation
**SHOULD** use this camera as the “active camera”. When there are
multiple cameras being controlled by the user, the implementation
**MAY** select one such camera or construct a synthetic camera to use as
the “active camera” (for example the midpoint of two stereoscopic camera
positions). When zero cameras are being controlled by the user but views
from one or more cameras are being displayed to the user, the
implementation **SHOULD** select one of the cameras that is being
displayed as the “active camera”.

The `position` read-only property represents the “active camera”
position in the global space using the glTF coordinate system. The
`rotation` read-only property represents the “active camera” rotation
quaternion (using XYZW notation); the identity quaternion corresponds to
the camera orientation defined in the glTF 2.0 Specification.

If the “active camera” uses a perspective projection, the `aspectRatio`,
`yfov`, `znear`, and `zfar` read-only properties nested in the
`perspective` path represent the aspect ratio (width over height),
vertical field of view in radians, distance to the near clipping plane,
and distance to the far clipping plane respectively. If the far clipping
plane is at infinity, the `zfar` value is infinity. If the “active
camera” does not use a perspective projection, all these four values are
NaNs.

If the “active camera” uses an orthographic projection, the `xmag`,
`ymag`, `znear`, and `zfar` read-only properties nested in the
`orthographic` path represent the half the orthographic width, half the
orthographic height, distance to the near clipping plane, and distance
to the far clipping plane respectively. If the “active camera” does not
use an orthographic projection, all these four values are NaNs.

An implementation **MAY** provide no “active camera” data, for example
for privacy reasons or if no cameras are being displayed to the user. If
the “active camera” position is unavailable, the `position` property
**MUST** be set to all NaNs; if the “active camera” rotation is
unavailable, the `rotation` property **MUST** be set to all NaNs; if the
“active camera” projection is unavailable, all properties corresponding
to the projection information **MUST** be set to NaNs.

The following pointers represent the read-only properties defined in
this section.

| Pointer | Type |
|----|----|
| `/extensions/KHR_interactivity/activeCamera/rotation` | `float4` |
| `/extensions/KHR_interactivity/activeCamera/position` | `float3` |
| `/extensions/KHR_interactivity/activeCamera/perspective/aspectRatio` | `float` |
| `/extensions/KHR_interactivity/activeCamera/perspective/yfov` | `float` |
| `/extensions/KHR_interactivity/activeCamera/perspective/znear` | `float` |
| `/extensions/KHR_interactivity/activeCamera/perspective/zfar` | `float` |
| `/extensions/KHR_interactivity/activeCamera/orthographic/xmag` | `float` |
| `/extensions/KHR_interactivity/activeCamera/orthographic/ymag` | `float` |
| `/extensions/KHR_interactivity/activeCamera/orthographic/znear` | `float` |
| `/extensions/KHR_interactivity/activeCamera/orthographic/zfar` | `float` |

### Animation State

To efficiently control animations, graphs usually need to access various
states specific to glTF animation objects. The interactivity extension
adds the following five runtime properties to the glTF animation
objects.

The `isPlaying` read-only property is true when the animation is
playing, false otherwise.

The `minTime` and `maxTime` read-only properties represent the
timestamps of the first and the last keyframes as stored in the glTF
animation object. The values **MUST** be derived from the `min` and
`max` properties of the used sampler input accessors. Unused animation
samplers, i.e., samplers not referenced by the animation channels,
**MUST** be ignored. If the animation object is invalid as defined in
the core glTF 2.0 specification, these properties **MUST** return NaNs.

> [!TIP]
> As defined in the base glTF 2.0 specification, animated properties are
> snapped to the closest keyframes if the requested timestamp is between
> zero and the timestamp of the first available keyframe. The `minTime`
> property could be used to query the timestamp of the animation’s
> earliest keyframe data and start the animation from that point if the
> initial delay potentially present in the animation data needs to be
> skipped.

The `playhead` read-only property represents the current animation
position within the glTF animation data. For valid glTF animations, the
property value is equal to the last effective timestamp, so it is always
greater than or equal to zero and less than or equal to `maxTime`.
Before the animation start, this property value is zero; when the
animation stops, the property retains its last value until the animation
is restarted. For invalid glTF animations, the property value is always
NaN.

The `virtualPlayhead` read-only property represents the current
animation position on the infinite timeline that is used for the input
value sockets of the `animation/start` and `animation/stop` operations.
For valid glTF animations, the property value is equal to the last
requested timestamp. Before the animation start, this property is zero;
when the animation stops, the property value retains its last value
until the animation is restarted. For invalid glTF animations, the
property value is always NaN.

The following pointers represent the read-only properties defined in
this section.

| Pointer                                                       | Type    |
|---------------------------------------------------------------|---------|
| `/animations/[]/extensions/KHR_interactivity/isPlaying`       | `bool`  |
| `/animations/{}/extensions/KHR_interactivity/isPlaying`       | `bool`  |
| `/animations/[]/extensions/KHR_interactivity/minTime`         | `float` |
| `/animations/{}/extensions/KHR_interactivity/minTime`         | `float` |
| `/animations/[]/extensions/KHR_interactivity/maxTime`         | `float` |
| `/animations/{}/extensions/KHR_interactivity/maxTime`         | `float` |
| `/animations/[]/extensions/KHR_interactivity/playhead`        | `float` |
| `/animations/{}/extensions/KHR_interactivity/playhead`        | `float` |
| `/animations/[]/extensions/KHR_interactivity/virtualPlayhead` | `float` |
| `/animations/{}/extensions/KHR_interactivity/virtualPlayhead` | `float` |

### Delay References

To check if a given reference value represents a valid delay object, the
behavior graph can query the runtime value of the corresponding
read-only virtual property using the `pointer/get` operation as
described in this section.

If the input reference value is not null and it is contained in the
dynamic array of delay activation references (see the `flow/setDelay`
operation), the `pointer/get` operation succeeds and thus sets the
`isValid` output value to true and the `value` output value to the input
reference value.

If the input reference value is null or it is not contained in the
dynamic array of delay activation references, the `pointer/get`
operation fails and thus sets the `isValid` output value to false and
the `value` output value to null.

The following pointer represents the read-only property defined in this
section.

| Pointer                                   | Type  |
|-------------------------------------------|-------|
| `/extensions/KHR_interactivity/delays/{}` | `ref` |

### Event References

To check if a given reference value represents an event object, the
behavior graph can query the runtime value of the corresponding
read-only virtual property using the `pointer/get` operation as
described in this section.

If the input reference value is not null and it was produced by an event
operation, i.e., it is an event reference, the `pointer/get` operation
succeeds and thus sets the `isValid` output value to true and the
`value` output value to the input reference value. The internal state of
the event object has no effect on this operation.

If the input reference value is null or it was not produced by an event
operation, i.e., it is not an event reference, the `pointer/get`
operation fails and thus sets the `isValid` output value to false and
the `value` output value to null.

The following pointer represents the read-only property defined in this
section.

| Pointer                                   | Type  |
|-------------------------------------------|-------|
| `/extensions/KHR_interactivity/events/{}` | `ref` |

# JSON Syntax

## General

A `KHR_interactivity` extension object is added to the root-level
`extensions` property. It contains an array of behavior graphs (named
`graphs`) each element of which is a JSON object containing five arrays
corresponding to five interactivity concepts: `types`, `variables`,
`events`, `declarations`, and `nodes`, and an optional `graph` property
that selects the default graph to use.

The `graphs` array **MUST NOT** have more than 2147483648 elements.

Different elements of the `graphs` array are completely isolated from
each other and exist in separate scopes. One invalid graph does not
invalidate other elements of the `graphs` array.

As with the core glTF spec, if a JSON array is empty, it **MUST** be
omitted from JSON.

``` javascript
{
  "asset": {
    "version": "2.0"
  },
  "extensionsUsed": [ "KHR_interactivity" ],
  "extensions": {
    "KHR_interactivity": {
      "graphs": [
        {
          "types": [
            //
          ],
          "variables": [
            //
          ],
          "events": [
            //
          ],
          "declarations": [
            //
          ],
          "nodes": [
            //
          ]
        }
      ],
      "graph": 0
    }
  }
}
```

The `graph` property refers to the `graphs` array element that
**SHOULD** be selected by default by the execution environment. If the
`graph` property is undefined, its value is implicitly set to zero. If
the `graph` property is not a non-negative integer less than the length
of the `graphs` array, the interactivity extension object is invalid.

If the currently selected graph is invalid or if the interactivity
extension object is invalid, implementations **MAY** treat the asset as
not having interactivity at all.

## Types

The `types` array defines mappings between type indices used by the
graph and the recognized type signatures. Each entry in this array
denotes a distinct type.

The `types` array **MUST NOT** have more than 2147483648 elements.

> [!NOTE]
> This example defines type `0` as **float2**, type `1` as **int**, and
> type `2` as **float**:
>
> ``` json
> "types": [
>   { "signature": "float2" },
>   { "signature": "int" },
>   { "signature": "float" }
> ]
> ```

The value of the `signature` property **MUST** be one of the value types
defined in this extension specification or `"custom"`. In the latter
case, the custom type semantics **MUST** be provided by an additional
extension.

Values of the `signature` property are case-sensitive.

Non-custom signatures **MUST NOT** appear more than once in this array;
if two or more entries of the `types` array have the same non-custom
signature, the graph is invalid and **MUST** be rejected. Extensions or
extras present on the types defined by this Specification do not change
type semantics.

> [!NOTE]
> This means that, for example, two entries with the signature `"int"`
> are still disallowed even if they have extensions and/or extras.

## Variables

The `variables` array defines variables with their types and optional
initial values.

The `variables` array **MUST NOT** have more than 2147483648 elements.

> [!NOTE]
> This example defines two variables of `float2` type; the first is
> explicitly initialized to `[0.5, 0.5]` and the second is implicitly
> initialized to `[NaN, NaN]`.
>
> ``` json
> "types": [
>   { "signature": "float2" }
> ],
> "variables": [
>   {
>     "type": 0,
>     "value": [ 0.5, 0.5 ]
>   },
>   {
>     "type": 0
>   }
> ]
> ```

The type of the variable is determined by the **REQUIRED** `type`
property that points to the element of the `types` array. If the `type`
property is undefined or if its value is not a non-negative integer less
than the length of the `types` array, the variable is invalid and the
graph **MUST** be rejected.

The `value` property is an array that defines the initial variable
value. If the `value` property is undefined, the variable is initialized
to the default value of its type. The following table defines array
lengths and default values for all value types defined in this
Specification.

| Type       | Array length | Default value               |
|------------|--------------|-----------------------------|
| `bool`     | 1            | Boolean false               |
| `float`    | 1            | Floating-point NaN          |
| `float2`   | 2            | Two floating-point NaNs     |
| `float3`   | 3            | Three floating-point NaNs   |
| `float4`   | 4            | Four floating-point NaN     |
| `float2x2` | 4            | Four floating-point NaNs    |
| `float3x3` | 9            | Nine floating-point NaNs    |
| `float4x4` | 16           | Sixteen floating-point NaNs |
| `int`      | 1            | Integer zero                |
| `ref`      | 1            | Null reference              |

Values for vector types use the XYZW order of components, that is X
component is stored in the array element with index 0, Y component is
stored in the array element with index 1, and so forth.

Values for matrix types use the column-major order of elements. For
example, elements of a 2x2 matrix are stored as
`[c0r0, c0r1, c1r0, c1r1]`, where `c0r0` is the element in the first
column and first row, `c0r1` is the element in the first column and
second row, and so forth.

Values for the reference type are specified using static JSON Pointers
without any template parameters. If the JSON pointer can be resolved
against the glTF asset to a valid reference value, that value is used;
if the pointer cannot be resolved, the reference value is null.

If the `value` property array length does not match the array length for
the specified type, the variable is invalid and the graph **MUST** be
rejected.

If the variable type is **bool** and the only array element is not a
JSON boolean literal, i.e., neither `true` nor `false`, the variable is
invalid and the graph **MUST** be rejected.

If the variable type is any of the **floatN** or **floatNxN** types and
any of the array elements is not a JSON number, the variable is invalid
and the graph **MUST** be rejected.

If the variable type is **int** and the only array element is not a JSON
number exactly representable as a 32-bit signed integer, the variable is
invalid and the graph **MUST** be rejected.

If the variable type is **ref** and the only array element is not a JSON
string or it is not a syntactically valid JSON Pointer as defined in
[RFC 6901](#rfc6901), the variable is invalid and the graph **MUST** be
rejected.

If the variable type is custom, the `value` property is defined by the
extension defining the custom type.

## Events

The `events` array defines external ids and value sockets for custom
events.

The `events` array **MUST NOT** have more than 2147483648 elements.

> [!NOTE]
> This example defines two custom events. The first event is internal to
> the graph and has no value sockets; the second event has an external
> id `"checkout"` and one integer value socket with id `"variant"` and
> an initial value of -1.
>
> ``` json
> "types": [
>   { "signature": "int" }
> ],
> "events": [
>   { },
>   {
>     "id": "checkout",
>     "values": {
>       "variant": {
>         "type": 0,
>         "value": [ -1 ]
>       }
>     }
>   }
> ]
> ```

The event id is an application-specific event identifier recognized by
the execution environment. If the `id` property is undefined, the event
is considered internal to the graph. If the same id is defined for two
or more events, the graph is invalid and **MUST** be rejected.

The properties of the `values` object define ids and the values of those
properties define types and optional initial values of the value sockets
associated with the event. If the `values` object is undefined, the
event has no associated value sockets.

Socket ids defined by the properties of the `values` object are
case-sensitive. The `values` object **MUST NOT** contain an `event`
property.

The type of the event value socket is determined by the **REQUIRED**
`type` property that points to the element of the `types` array. If the
`type` property is undefined or its value is not a non-negative integer
less than the length of the `types` array, the event is invalid and the
graph **MUST** be rejected.

The `value` property of the event value socket has the same syntax and
semantics as the `value` property of variable definitions (see the
previous section).

## Declarations

The `declarations` array defines mappings between interactivity node
declaration indices used by the graph and the operations.

The `declarations` array **MUST NOT** have more than 2147483648
elements.

> [!NOTE]
> This example defines declaration `0` as `math/min` and declaration `1`
> as `variable/set`.
>
> ``` json
> "declarations": [
>   { "op": "math/min" },
>   { "op": "variable/set" }
> ]
> ```

The `op` property is **REQUIRED**; it contains the operation identifier;
if this property is undefined, the declaration is invalid and the graph
**MUST** be rejected.

Values of the `op` property are case-sensitive.

If the operation is not defined by this Specification, the `extension`
property **MUST** be defined and it contains the additional
interactivity extension name that defines the operation. If the
`extension` property is not defined and the operation is not defined by
this Specification, the declaration is invalid and the graph **MUST** be
rejected.

Values of the `extension` property are case-sensitive.

If the operation is defined in an additional interactivity extension and
it uses input value sockets, the `inputValueSockets` object **MUST** be
present. Its properties define ids and the values of its properties
define types of the input value sockets. If the `inputValueSockets`
object is undefined, the operation has no input value sockets.

If the operation is defined in an additional interactivity extension and
it uses output value sockets, the `outputValueSockets` object **MUST**
be present. Its properties define ids and the values of its properties
define types of the output value sockets. If the `outputValueSockets`
object is undefined, the operation has no output value sockets.

Socket ids defined by the properties of the `inputValueSockets` and
`outputValueSockets` objects are case-sensitive.

If the `extension` property is undefined, the operation with all its
value sockets is assumed to be provided by this Specification and
therefore `inputValueSockets` and `outputValueSockets` objects **MUST
NOT** be defined.

> [!NOTE]
> This example defines a declaration that maps to the `event/onSelect`
> operation defined in the `KHR_node_selectability` extension. The
> operations has three output value sockets and zero input value
> sockets.
>
> ``` json
> "types": [
>   { "signature": "ref" },
>   { "signature": "int" },
>   { "signature": "float3" }
> ],
> "declarations": [
>   {
>     "op": "event/onSelect",
>     "extension": "KHR_node_selectability",
>     "outputValueSockets": {
>       "selectedNode":    { "type": 0 },
>       "controllerIndex": { "type": 1 },
>       "selectionPoint":  { "type": 2 }
>     }
>   }
> ]
> ```

The type of the value socket is determined by the **REQUIRED** `type`
property that points to the element of the `types` array. If the `type`
property is undefined or if its value is not a non-negative integer less
than the length of the `types` array, the declaration is invalid and the
graph **MUST** be rejected.

Two declarations are considered equal if their `op` properties have the
same value, their `extension` properties (if present) have the same
value, and their `inputValueSockets` objects (if present) define the
same socket ids with the same type indices. The `declarations` array
**MUST NOT** have equal declarations; if two or more declarations are
equal, all of them are invalid and the graph **MUST** be rejected.

> [!NOTE]
> All three declarations in this example are equal thus they all are
> invalid.
>
> ``` json
> "types": [
>   { "signature": "int" },
>   { "signature": "float" }
> ],
> "declarations": [
>   {
>     "op": "math/min3",
>     "extension": "VND_interactivity_min3",
>     "inputValueSockets": {
>       "a": { "type": 0 },
>       "b": { "type": 0 },
>       "c": { "type": 0 }
>     },
>     "outputValueSockets": {
>       "value": { "type": 0 }
>     }
>   },
>   {
>     "op": "math/min3",
>     "extension": "VND_interactivity_min3",
>     "inputValueSockets": {
>       "b": { "type": 0 },
>       "a": { "type": 0 },
>       "c": { "type": 0 }
>     },
>     "outputValueSockets": {
>       "value": { "type": 0 }
>     }
>   },
>   {
>     "op": "math/min3",
>     "extension": "VND_interactivity_min3",
>     "inputValueSockets": {
>       "a": { "type": 0 },
>       "b": { "type": 0 },
>       "c": { "type": 0 }
>     },
>     "outputValueSockets": {
>       "value": { "type": 1 }
>     }
>   }
> ]
> ```

### Unsupported Declarations

A declaration is considered unsupported if any of the following
conditions is true:

- The declaration refers to an unsupported or disabled extension.

- The referred extension does not define the operation.

- Neither of the definitions of the operation in the referred extension
  has exactly the same input and output value sockets with regards to
  their ids and types.

If the declaration is unsupported, the interactivity nodes referring to
it are demoted to [“no-op” nodes](#nodes-noop).

## Nodes

The `nodes` array defines the interactivity nodes and their connections.

Each element of the `nodes` array specifies the interactivity node’s
operation via a declaration index, sources for the input value sockets,
pointers for the output flow sockets, and its configuration.

The `nodes` array **MUST NOT** have more than 2147483648 elements.

### Operation

The operation is specified by the **REQUIRED** `declaration` property
that points to an element of the `declarations` array. If that property
is undefined or if its value is not a non-negative integer less than the
number of declarations, the interactivity node is invalid and the graph
**MUST** be rejected.

> [!NOTE]
> An interactivity node with the `math/E` operation with its
> declaration.
>
> ``` json
> "declarations": [
>   { "op": "math/E" }
> ],
> "nodes": [
>   { "declaration": 0 }
> ]
> ```

### Input Value Sockets

If the operation has input value sockets, the `values` object **MUST**
be defined and it **MUST **have properties matching the input value
socket ids defined by the declaration and/or configuration; if the
`values` object does not have a corresponding property for each input
value socket id, the interactivity node is invalid and the graph** MUST
**be rejected. The `values` object** MAY **have additional properties
not matching the input value socket ids of the operation; such
properties have no effect on the operation but their values** MUST
**still conform to the JSON schema and other rules defined in this
section. If the operation does not have input value sockets, the
`values` object** SHOULD NOT**\* be defined.

Some operations, e.g., `pointer/get` or `variable/get`, define their
input value socket ids and/or types based on the operation’s
configuration. Therefore, the configuration **MAY** need to be processed
prior to the input value sockets.

The values of the `values` object properties are JSON objects that
define effective input value socket types and value sources. Each value
source is either an inline constant value, a
[type-default](#variables-types) value, or a reference to another
interactivity node’s output value socket. If no source is defined or if
the socket type does not match the declaration, the interactivity node
is invalid and the graph **MUST** be rejected.

Socket ids defined by the properties of the `values` object are
case-sensitive.

Some operations have multiple variants to support the same operation on
different input value socket types. In all such cases, the variants
share the same set of input value socket ids and only their types
differ. Therefore, effective input value socket types **MAY** be needed
to fully resolve the operation.

If the operation does not support the input value socket types used by
the interactivity node, the interactivity node is invalid and the graph
**MUST** be rejected.

> [!NOTE]
> For example, the `math/add` operation defined in this Specification
> supports all numeric types, i.e., integers, vectors, and matrices, but
> only for matching input value socket types. So any interactivity node
> that refers to `math/add` and uses different types for its `a` and `b`
> input value sockets would be invalid.

#### Inline Values

If the `value` property is defined in the object representing the input
value socket, the input value socket source is an inline constant.

The `value` property has the same syntax as the `value` property of
variable definitions. The type of the input value socket is determined
by the `type` property that points to the element of the `types` array
and **MUST** be defined. If the `type` property value is not a
non-negative integer less than the length of the `types` array, the node
is invalid and the graph **MUST** be rejected.

> [!NOTE]
> An interactivity node with the `math/add` operation with two integer
> inline values: 1 and 2.
>
> ``` json
> "types": [
>   { "signature": "int" }
> ],
> "declarations": [
>   { "op": "math/add" }
> ],
> "nodes": [
>   {
>     "declaration": 0,
>     "values": {
>       "a": { "value": [ 1 ], "type": 0 },
>       "b": { "value": [ 2 ], "type": 0 }
>     }
>   }
> ]
> ```

#### Output Socket References

If the `node` property is defined in the object representing the input
value socket, the input value socket source is the output value socket
of another interactivity node of the graph. If both `node` and `value`
properties are defined for the same input value socket, the
interactivity node is invalid and the graph **MUST** be rejected.

The `node` property contains the index of the other interactivity node
and the `socket` property contains the id of the output socket of that
node.

If the `node` property value is not a non-negative integer less than the
index of the current interactivity node, the interactivity node is
invalid and the graph **MUST** be rejected.

> [!NOTE]
> This ensures that value sockets do not form loops and simplifies input
> value socket type derivation.

If the `socket` property is defined, it **MUST** correspond to an output
value socket existing in the referenced interactivity node, otherwise
the current interactivity node is invalid and the graph **MUST** be
rejected. If the `socket` property is undefined, the default socket id
`"value"` is used implicitly. Therefore, if the referenced interactivity
node does not have an output value socket with id `"value"`, the
`socket` property **MUST** be defined.

Socket ids referenced by the `socket` property are case-sensitive.

If both `node` and `type` properties are defined, the type referred by
the `type` property **MUST** match the type of the referenced output
value socket; if the types do not match, the current interactivity node
is invalid and the graph **MUST** be rejected.

> [!NOTE]
> Although explicitly defining input value socket types is generally
> redundant for input value sockets referring to other interactivity
> nodes, providing this information could improve debugging experience
> during graph development.

> [!NOTE]
> An interactivity node with the `math/sub` operation with two input
> value sockets referring to output value sockets of two other
> interactivity nodes. The input socket `a` refers to the output socket
> id explicitly and the input socket `b` relies on the implicit output
> socket id.
>
> ``` json
> "types": [
>   { "signature": "float" }
> ],
> "declarations": [
>   { "op": "math/Pi" },
>   { "op": "math/E" },
>   { "op": "math/sub" }
> ],
> "nodes": [
>   { "declaration": 0 },
>   { "declaration": 1 },
>   {
>     "declaration": 2,
>     "values": {
>       "a": { "node": 0, "socket": "value" },
>       "b": { "node": 1 }
>     }
>   }
> ]
> ```

#### Type-Default Values

If neither `value` nor `node` properties are defined in the object
representing the input value socket, the input value socket has a
[type-default](#variables-types) value determined by the `type` property
that points to the element of the `types` array and **MUST** be defined.
If the `type` property value is not a non-negative integer less than the
length of the `types` array, the node is invalid and the graph **MUST**
be rejected.

> [!NOTE]
> An interactivity node with the `math/isNaN` operation with a
> type-default input value socket. The output value of this
> interactivity node is true because the input value socket `a` has a
> constant value of NaN (type-default for `float`).
>
> ``` json
> "types": [
>   { "signature": "float" }
> ],
> "declarations": [
>   { "op": "math/isNaN" }
> ],
> "nodes": [
>   {
>     "declaration": 0,
>     "values": {
>       "a": { "type": 0 }
>     }
>   }
> ]
> ```

### Output Flow Socket Pointers

Pointers for the output flow sockets are defined in the `flows` object
of the interactivity node.

Properties of the `flows` object link output flow sockets of the current
interactivity node with input flow sockets of other interactivity nodes.
If an output flow socket id of the current interactivity node is not
present in the `flows` object, that output flow socket is unconnected
and activating it has have no effect.

Socket ids defined by the properties of the `flows` object are
case-sensitive.

The `flows` object **MAY** contain properties not corresponding to
output flows of the current interactivity node; such properties do not
affect functionality of the interactivity node but their values **MUST**
still be validated as described below.

Each property of the `flows` object is a JSON object containing a
**REQUIRED** `node` property and an **OPTIONAL** `socket` property. The
`node` property contains the index of the other interactivity node and
the `socket` property contains the id of the input flow socket of that
interactivity node.

Socket ids referenced by the `socket` property are case-sensitive.

The `node` property value **MUST** be an integer greater than the index
of the current interactivity node and less then the total number of
interactivity nodes, otherwise the interactivity node is invalid and the
graph **MUST** be rejected.

> [!NOTE]
> This ensures that flow sockets do not form loops.

If the `socket` property is undefined, it has a default value of `"in"`.

If the `socket` property value corresponds to an input flow socket
existing in the referenced interactivity node, the output flow socket of
the current interactivity node is connected to the referenced input flow
socket. If the specified input flow socket does not exist in the
referenced interactivity node, the output flow socket of the current
interactivity node is unconnected and activating it **MUST** have no
effect.

> [!NOTE]
> An interactivity node with the `flow/setDelay` operation that starts
> an animation after a certain amount of time since the start of the
> graph execution.
>
> The `out` output flow of the `event/onStart` interactivity node is
> connected to the `in` input flow of the `flow/setDelay` interactivity
> node explicitly. Then, the `out` output flow of the latter
> interactivity node is connected to the `in` input flow of the
> `animation/start` interactivity node implicitly.
>
> ``` json
> "types": [
>   { "signature": "float" },
>   { "signature": "int" }
> ],
> "declarations": [
>   { "op": "event/onStart" },
>   { "op": "flow/setDelay" },
>   { "op": "math/Inf" },
>   { "op": "animation/start" }
> ],
> "nodes": [
>   {
>     "declaration": 0,
>     "flows": {
>       "out": { "node": 1, "socket": "in" }
>     }
>   },
>   {
>     "declaration": 1,
>     "values": {
>       "duration": { "type": 0, "value": [ 5 ] }
>     },
>     "flows": {
>       "out": { "node": 3 }
>     }
>   },
>   {
>     "declaration": 2
>   },
>   {
>     "declaration": 3,
>     "values": {
>       "animation": { "type": 1 },
>       "startTime": { "type": 0, "value": [ 0 ] },
>       "endTime": { "node": 2 },
>       "speed": { "type": 0, "value": [ 1 ] }
>     }
>   }
> ]
> ```

### Configuration

Configuration properties are defined in the `configuration` object of
the interactivity node.

Each property of the `configuration` object is a JSON object with a
single `value` property. The type of the `value` property is determined
by the operation’s specification, i.e., configuration values are
implicitly typed.

> [!NOTE]
> Some operations have configuration values of types that cannot be
> expressed with the explicit types defined in this Specification.

Refer to the [Configuration](#nodes-configuration) section and to
individual operation specifications for details regarding configuration
validity.

Configuration properties defined by the properties of the
`configuration` object are case-sensitive.

Configuration values use JSON arrays similarly to other uses of inline
values.

| Configuration Type | JSON Type |
|----|----|
| `bool` | Array of one boolean |
| `int` | Array of one number exactly representable as a 32-bit signed integer |
| `int[]` | Array of one or more numbers exactly representable as 32-bit signed integers |
| `string` | Array of one JSON string |

> [!NOTE]
> An interactivity node with the `variable/set` operation that sets a
> custom variable with index `0` when the start event happens.
>
> ``` json
> "types": [
>   { "signature": "float" }
> ],
> "variables": [
>   { "type": 0 }
> ],
> "declarations": [
>   { "op": "event/onStart" },
>   { "op": "variable/set" }
> ],
> "nodes": [
>   {
>     "declaration": 0,
>     "flows": {
>       "out": { "node": 1 }
>     }
>   },
>   {
>     "declaration": 1,
>     "configuration": {
>       "variables": { "value": [ 0 ] }
>     },
>     "values": {
>       "0": { "type": 0, "value": [ 1.5 ] }
>     }
>   }
> ]
> ```


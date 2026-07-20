# Functional Specification

## Operations

### Math Operations

Starting from this section, `floatN` is a placeholder for `float`,
`float2`, `float3`, and `float4` types; `floatNxN` is a placeholder for
`float2x2`, `float3x3`, and `float4x4` types.

All value sockets of `floatN` or `floatNxN` types have the same type
within an interactivity node.

#### Constants

##### E

|                          |               |                   |
|--------------------------|---------------|-------------------|
| **Operation**            | `math/E`      | Euler’s number    |
| **Output value sockets** | `float value` | 2.718281828459045 |

##### Pi

|  |  |  |
|----|----|----|
| **Operation** | `math/Pi` | Ratio of a circle’s circumference to its diameter |
| **Output value sockets** | `float value` | 3.141592653589793 |

##### Tau

|  |  |  |
|----|----|----|
| **Operation** | `math/Tau` | Ratio of a circle’s circumference to its radius |
| **Output value sockets** | `float value` | 6.283185307179586 |

##### Infinity

|                          |               |                   |
|--------------------------|---------------|-------------------|
| **Operation**            | `math/Inf`    | Positive infinity |
| **Output value sockets** | `float value` | *Infinity*        |

> [!TIP]
> To get negative infinity, combine this operation with `math/neg`.

##### Not a Number

|                          |               |              |
|--------------------------|---------------|--------------|
| **Operation**            | `math/NaN`    | Not a Number |
| **Output value sockets** | `float value` | *NaN*        |

#### Arithmetic Operations

These all operate component-wise. The description is per component.

If any input value component is *NaN*, the corresponding output value
component is also *NaN*.

##### Absolute Value

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/abs</code></p></td>
<td style="text-align: left;"><p>Absolute value operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">$\begin{cases}
                                  -a &amp; \text{if } a \lt 0 \\
                                  +0 &amp; \text{if } a = \pm0 \\
                                   a &amp; \text{if } a \gt 0
                                \end{cases}$</span></p></td>
</tr>
</tbody>
</table>

##### Sign

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/sign</code></p></td>
<td style="text-align: left;"><p>Sign operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">$\begin{cases}
                                  -1 &amp; \text{if } a \lt 0 \\
                                   a &amp; \text{if } a = \pm0 \\
                                  +1 &amp; \text{if } a \gt 0
                                \end{cases}$</span></p></td>
</tr>
</tbody>
</table>

##### Truncate

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/trunc</code></p></td>
<td style="text-align: left;"><p>Truncate operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Integer value equal to the nearest
integer to <span class="math inline"><em>a</em></span> whose absolute
value is not larger than the absolute value of <span
class="math inline"><em>a</em></span></p></td>
</tr>
</tbody>
</table>

If the argument is infinity, it is returned unchanged.

##### Floor

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/floor</code></p></td>
<td style="text-align: left;"><p>Floor operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline"><em>f</em><em>l</em><em>o</em><em>o</em><em>r</em>(<em>a</em>)</span>,
value equal to the nearest integer that is less than or equal to <span
class="math inline"><em>a</em></span></p></td>
</tr>
</tbody>
</table>

If the argument is infinity, it is returned unchanged.

##### Ceil

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/ceil</code></p></td>
<td style="text-align: left;"><p>Ceil operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline"><em>c</em><em>e</em><em>i</em><em>l</em>(<em>a</em>)</span>,
value equal to the nearest integer that is greater than or equal to
<span class="math inline"><em>a</em></span></p></td>
</tr>
</tbody>
</table>

If the argument is infinity, it is returned unchanged.

##### Round

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/round</code></p></td>
<td style="text-align: left;"><p>Round operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Value equal to the integer nearest to
<span class="math inline"><em>a</em></span></p></td>
</tr>
</tbody>
</table>

Half-way cases **MUST** be rounded away from zero. Negative values
greater than `-0.5` **MUST** be rounded to negative zero.

If the argument is infinity, it is returned unchanged.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> a < 0 ? -Math.round(-a) : Math.round(a)
> ```

##### Fraction

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/fract</code></p></td>
<td style="text-align: left;"><p>Fractional operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline"><em>a</em> − <em>f</em><em>l</em><em>o</em><em>o</em><em>r</em>(<em>a</em>)</span></p></td>
</tr>
</tbody>
</table>

##### Negation

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/neg</code></p></td>
<td style="text-align: left;"><p>Negation operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">−<em>a</em></span></p></td>
</tr>
</tbody>
</table>

##### Addition

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/add</code></p></td>
<td style="text-align: left;"><p>Addition operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>First addend</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Second addend</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Sum, <span
class="math inline"><em>a</em> + <em>b</em></span></p></td>
</tr>
</tbody>
</table>

##### Subtraction

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/sub</code></p></td>
<td style="text-align: left;"><p>Subtraction operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Minuend</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Subtrahend</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Difference, <span
class="math inline"><em>a</em> − <em>b</em></span></p></td>
</tr>
</tbody>
</table>

##### Multiplication

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/mul</code></p></td>
<td style="text-align: left;"><p>Multiplication operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>First factor</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Second factor</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Product, <span
class="math inline"><em>a</em> * <em>b</em></span></p></td>
</tr>
</tbody>
</table>

For matrix arguments, this operation performs per-element
multiplication.

> [!NOTE]
> See `math/matMul` for matrix multiplication.

##### Division

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/div</code></p></td>
<td style="text-align: left;"><p>Division operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Dividend</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Divisor</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Quotient, <span
class="math inline"><em>a</em>/<em>b</em></span></p></td>
</tr>
</tbody>
</table>

##### Remainder

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/rem</code></p></td>
<td style="text-align: left;"><p>Remainder operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Dividend</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Divisor</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">$\begin{cases}
                                  \mathit{NaN} &amp; \text{if } a = \pm
\infty \text{ or } b = \pm 0 \\
                                  a &amp; \text{if } a \ne \pm \infty
\text{ and } b = \pm \infty \\
                                  a - (b \cdot
\operatorname{trunc}(\frac{a}{b})) &amp; \text{otherwise}
                                \end{cases}$</span></p></td>
</tr>
</tbody>
</table>

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> a % b
> ```

##### Minimum

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/min</code></p></td>
<td style="text-align: left;"><p>Minimum operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>First argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Second argument</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Smallest of the arguments</p></td>
</tr>
</tbody>
</table>

For the purposes of this operation, negative zero is less than positive
zero.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.min(a, b)
> ```

##### Maximum

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/max</code></p></td>
<td style="text-align: left;"><p>Maximum operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>First argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Second argument</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p>Largest of the arguments</p></td>
</tr>
</tbody>
</table>

For the purposes of this operation, negative zero is less than positive
zero.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.max(a, b)
> ```

##### Clamp

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/clamp</code></p></td>
<td style="text-align: left;"><p>Clamp operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Value to clamp</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>First boundary</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN c</code> or<br />
<code>floatNxN c</code></p></td>
<td style="text-align: left;"><p>Second boundary</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">min (max (<em>a</em>, min (<em>b</em>, <em>c</em>)), max (<em>b</em>, <em>c</em>))</span></p></td>
</tr>
</tbody>
</table>

This operation is defined in terms of `math/min` and `math/max`
operations defined above.

> [!NOTE]
> This operation correctly handles a case when $`b`$ is greater than
> $`c`$.

##### Saturate

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/saturate</code></p></td>
<td style="text-align: left;"><p>Saturate operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Value to saturate</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">min (max (<em>a</em>, 0), 1)</span></p></td>
</tr>
</tbody>
</table>

This operation is defined in terms of `math/min` and `math/max`
operations defined above.

##### Interpolate

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/mix</code></p></td>
<td style="text-align: left;"><p>Linear interpolation operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>Interpolated value at <span
class="math inline">0</span></p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Interpolated value at <span
class="math inline">1</span></p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN c</code> or<br />
<code>floatNxN c</code></p></td>
<td style="text-align: left;"><p>Unclamped interpolation
coefficient</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN value</code> or<br />
<code>floatNxN value</code></p></td>
<td style="text-align: left;"><p><span
class="math inline">(1 − <em>c</em>) * <em>a</em> + <em>c</em> * <em>b</em></span></p></td>
</tr>
</tbody>
</table>

##### Smooth Step

|  |  |  |
|----|----|----|
| **Operation** | `math/smoothStep` | Smooth step (Hermit interpolation) operation |
| **Input value sockets** | `floatN a` | First edge |
| `floatN b` | Second edge |  |
| `floatN c` | Value to interpolate |  |
| **Output value sockets** | `floatN value` | Computed interpolation coefficient |

Let

<div class="informalequation">

``` math
t = \operatorname{saturate}(\frac{c - \min(a, b)}{|b - a|})
```

</div>

Then the components of the `value` output socket value are computed as
the components of the following value:

<div class="informalequation">

``` math
t \cdot t \cdot (3 - 2 \cdot t)
```

</div>

This operation is defined in terms of `math/min` and `math/saturate`
operations defined above.

Since this operation is a shortcut for the combination of arithmetic
operations, NaN and infinity values are propagated accordingly.

> [!NOTE]
> This operation correctly handles a case when $`a`$ is greater than
> $`b`$.

#### Comparison Operations

If any input value is *NaN*, the output value is false.

For the purposes of these operations, negative zero is equal to positive
zero.

##### Equality

<table>
<colgroup>
<col style="width: 25%" />
<col style="width: 25%" />
<col style="width: 50%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: left;"><p><strong>Operation</strong></p></td>
<td style="text-align: left;"><p><code>math/eq</code></p></td>
<td style="text-align: left;"><p>Equality operation</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Input value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>floatN a</code> or<br />
<code>floatNxN a</code></p></td>
<td style="text-align: left;"><p>First argument</p></td>
</tr>
<tr>
<td style="text-align: left;"><p><code>floatN b</code> or<br />
<code>floatNxN b</code></p></td>
<td style="text-align: left;"><p>Second argument</p></td>
<td></td>
</tr>
<tr>
<td style="text-align: left;"><p><strong>Output value
sockets</strong></p></td>
<td style="text-align: left;"><p><code>bool value</code></p></td>
<td style="text-align: left;"><p>True if the input arguments are equal,
per-component; false otherwise</p></td>
</tr>
</tbody>
</table>

##### Less Than

|  |  |  |
|----|----|----|
| **Operation** | `math/lt` | Less than operation |
| **Input value sockets** | `float a` | First argument |
| `float b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a < b`$; false otherwise |

##### Less Than Or Equal To

|  |  |  |
|----|----|----|
| **Operation** | `math/le` | Less than or equal to operation |
| **Input value sockets** | `float a` | First argument |
| `float b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a <= b`$; false otherwise |

##### Greater Than

|  |  |  |
|----|----|----|
| **Operation** | `math/gt` | Greater than operation |
| **Input value sockets** | `float a` | First argument |
| `float b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a > b`$; false otherwise |

##### Greater Than Or Equal To

|  |  |  |
|----|----|----|
| **Operation** | `math/ge` | Greater than or equal operation |
| **Input value sockets** | `float a` | First argument |
| `float b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a >= b`$; false otherwise |

#### Special Operations

##### Is Not a Number

|  |  |  |
|----|----|----|
| **Operation** | `math/isNaN` | Not a Number check operation |
| **Input value sockets** | `float a` | Argument |
| **Output value sockets** | `bool value` | True if $`a`$ is *NaN*; false otherwise |

##### Is Infinity

|  |  |  |
|----|----|----|
| **Operation** | `math/isInf` | Infinity check operation |
| **Input value sockets** | `float a` | Argument |
| **Output value sockets** | `bool value` | True if $`a`$ is positive or negative infinity; false otherwise |

> [!TIP]
> To check whether a value is only a positive infinity, combine
> `math/eq` and `math/Inf` operations.
>
> To check whether a value is only a negative infinity, combine
> `math/eq`, `math/neg`, and `math/Inf` operations.

##### Select

|  |  |  |
|----|----|----|
| **Operation** | `math/select` | Conditional selection operation |
| **Input value sockets** | `bool condition` | Value selecting the value returned |
| `T a` | Positive selection option |  |
| `T b` | Negative selection option |  |
| **Output value sockets** | `T value` | $`a`$ if the `condition` input value is true; $`b`$ otherwise |

The type `T` represents any supported type including numeric, reference,
and custom types. It **MUST** be the same for the output value socket
and the input value sockets $`a`$ and $`b`$.

##### Switch

|  |  |  |
|----|----|----|
| **Operation** | `math/switch` | Conditionally output one of the input values |
| **Configuration** | `int[] cases` | The cases on which to perform the switch; empty in the default configuration |
| **Input value sockets** | `int selection` | The value on which the switch operates |
| `T <case>` | Zero or more input value sockets; `<case>` is an integer decimal number |  |
| `T default` | The value used when the `selection` input value is not present in the `cases` configuration array |  |
| **Output value sockets** | `T value` | The value taken from the selected input value socket |

> [!CAUTION]
> The configuration of this operation affects its value sockets.

The operation has zero or more `<case>` input value sockets
corresponding to the elements of the `cases` configuration array.

The type `T` represents any supported type including numeric, reference,
and custom types. The type of the `value` output value socket is the
same as the type of the `default` input value socket.

In the default configuration, the `cases` configuration array is empty
and the operation has only the `default` and `selection` input value
sockets.

The following procedure defines input value sockets generation from the
provided configuration:

1.  If the `cases` configuration property is not present or if it is not
    an array, ignore it and use the default configuration.

2.  If the `cases` configuration property is present and it is an array,
    then for each array element `C`:

    1.  if `C` is not a literal number or if it is not exactly
        representable as a 32-bit signed integer, ignore the `cases`
        property and use the default configuration;

        > [!TIP]
        > The integer representation check is implementable in
        > ECMAScript via the following expression:
        >
        > ``` js
        > C === (C | 0)
        > ```

    2.  convert `C` to a base-10 string representation `S` containing
        only decimal integers (ASCII characters `0x30 …​ 0x39`) and a
        leading minus sign (ASCII character `0x2D`) if `C` is negative;
        extra leading zeros **MUST NOT** be present;

    3.  add a value socket `S` to the set of the input value sockets of
        this operation or ignore it if an input value socket with the
        same id has been already added.

3.  If the number of generated value sockets plus two exceeds an
    implementation-defined limit on the maximum number of input value
    sockets, the graph **MUST** be rejected.

4.  Proceed with the generated input value sockets.

<div class="note">

<div class="title">

Examples

</div>

- If the `cases` configuration array is `[0.5, 1]`, the default
  configuration is used because `0.5` is not representable as a 32-bit
  signed integer.

- If the `cases` configuration array is `[-2147483649, 0]`, the default
  configuration is used because `-2147483649` is not representable as a
  32-bit signed integer.

- If the `cases` configuration array is `[-1.0, 0, 1]`, the output
  socket ids are exactly `"-1"`, `"0"`, and `"1"` because `-1.0` is
  equal to an integer `-1`.

- If the `cases` configuration array is `[0.1e1, 2, 2]`, the output
  socket ids are exactly `"1"` and `"2"` because `0.1e1` is equal to an
  integer `1` and the duplicate entry is ignored.

</div>

If the interactivity node’s JSON object does not contain all input value
sockets generated by the procedure above with the same type as the
`default` input value socket, the interactivity node is invalid and the
graph **MUST** be rejected.

<div class="note">

<div class="title">

Validation Examples

</div>

- If the interactivity node does not have `selection` or `default` input
  value sockets, then the interactivity node is invalid.

- If the interactivity node has a `selection` input value socket with
  any type other than integer, then the interactivity node is invalid.

- If the default configuration is used and the interactivity node has an
  integer `selection` input value socket and a `default` input value
  socket of any type, then the node is valid.

- If the `cases` configuration array is `[1, 2]` and the interactivity
  node does not have input value sockets with ids `1` and `2`, then the
  interactivity node is invalid.

- If the `cases` configuration array is `[1, 2]` and the interactivity
  node has an input value socket with id `1` and the same type as the
  type of the `default` input value socket and an input value socket
  with id `2` and any other type, then the interactivity node is
  invalid.

</div>

Extra input value sockets with ids not present in the output of the
procedure above do not affect the interactivity node’s operation and
validation but they still **MUST** have valid types and value sources.

<div class="note">

<div class="title">

Validation Examples

</div>

- If the default configuration is used and the interactivity node has an
  integer `selection` input value socket, a `default` input value socket
  of any type, and any other input value socket of any type, then the
  interactivity node is valid.

- If the `cases` configuration array is `[1]` and the interactivity node
  has an integer `selection` input value socket, a `default` input value
  socket of any type, an input value socket with id `1` and the same
  type as the type of the `default` input value socket, and any other
  input value socket of any type, then the interactivity node is valid.

</div>

This operation has no internal state.

The `value` output value is computed as follows:

1.  Evaluate all input value sockets.

2.  If the `cases` configuration array does not contain the `selection`
    input value:

    1.  set the `value` output value to the value of the `default` input
        value socket.

3.  If the `cases` configuration array contains the `selection` input
    value:

    1.  set the `value` output value to the value of the input value
        socket with id equal to the decimal string representation of the
        `selection` input value.

<div class="note">

<div class="title">

Operation Examples

</div>

- If the default configuration is used, the `value` output value is
  always the same as the `default` input value.

- If the `cases` configuration array is `[1]` and the `selection` input
  value is `1`, the `value` output value is the value of the input value
  socket with id `1`.

- If the `cases` configuration array is `[1]` and the `selection` input
  value is `2`, the `value` output value is the value of the `default`
  input value socket even if the interactivity node’s JSON has an input
  value socket with id `2`.

</div>

##### Random

|  |  |  |
|----|----|----|
| **Operation** | `math/random` | Random value generation operation |
| **Output value sockets** | `float value` | A pseudo-random number greater than or equal to zero and less than one |

> [!WARNING]
> This operation is not intended for any workflows that require
> cryptographically secure random numbers.

The value of the output value socket `value` **MUST** be initialized to
a random number on the first access. Any two accesses of the output
value socket `value` **MUST** return the same value if there were no
flow socket activations (of other interactivity nodes) between them.

> [!NOTE]
> This means that, e.g., an interactivity node with the `math/eq`
> operation having both its input value sockets connected to the same
> interactivity node with the `math/random` operation always returns
> true.

The value of the output value socket `value` **MUST** be updated when
accessed as a result of a new flow socket activation, including
self-activations of other interactivity nodes.

> [!NOTE]
> At the current state of the Specification, only `flow/while` and
> `flow/for` operations use self-activation of their input flow sockets.

#### Angle and Trigonometry Operations

Operation parameters specified as angle are assumed to be in units of
radians.

These all operate component-wise. The description is per component.

If any input value component is *NaN*, the corresponding output value
component is also *NaN*.

##### Degrees-To-Radians

|                          |                |                             |
|--------------------------|----------------|-----------------------------|
| **Operation**            | `math/rad`     | Converts degrees to radians |
| **Input value sockets**  | `floatN a`     | Value in degrees            |
| **Output value sockets** | `floatN value` | $`a * pi / 180`$            |

##### Radians-To-Degrees

|                          |                |                             |
|--------------------------|----------------|-----------------------------|
| **Operation**            | `math/deg`     | Converts radians to degrees |
| **Input value sockets**  | `floatN a`     | Value in radians            |
| **Output value sockets** | `floatN value` | $`a * 180 / pi`$            |

##### Sine

|  |  |  |
|----|----|----|
| **Operation** | `math/sin` | Sine function |
| **Input value sockets** | `floatN a` | Angle |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \mathit{NaN} & \text{if } a = \pm\infty \\
                                \sin(a) & \text{otherwise}
                              \end{cases}`$ |

##### Cosine

|  |  |  |
|----|----|----|
| **Operation** | `math/cos` | Cosine function |
| **Input value sockets** | `floatN a` | Angle |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                +1 & \text{if } a = \pm0 \\
                                \mathit{NaN} & \text{if } a = \pm\infty \\
                                \cos(a) & \text{otherwise}
                              \end{cases}`$ |

##### Tangent

|  |  |  |
|----|----|----|
| **Operation** | `math/tan` | Tangent function |
| **Input value sockets** | `floatN a` | Angle |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \mathit{NaN} & \text{if } a = \pm\infty \\
                                \tan(a) & \text{otherwise}
                              \end{cases}`$ |

> [!NOTE]
> Since $`a`$ cannot exactly represent $`\pm\frac{\pi}{2}`$, this
> function does not return infinity. The closest representable argument
> values would likely produce $`\pm16331239353195370`$.

##### Arcsine

|  |  |  |
|----|----|----|
| **Operation** | `math/asin` | Arcsine function |
| **Input value sockets** | `floatN a` | Sine value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \mathit{NaN} & \text{if } |a| \gt 1 \\
                                \arcsin(a) \in [-\frac{\pi}{2}; \frac{\pi}{2}] & \text{otherwise}
                              \end{cases}`$ |

##### Arccosine

|  |  |  |
|----|----|----|
| **Operation** | `math/acos` | Arccosine function |
| **Input value sockets** | `floatN a` | Cosine value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                +0 & \text{if } a = 1 \\
                                \mathit{NaN} & \text{if } |a| \gt 1 \\
                                \arccos(a) \in [0; \pi] & \text{otherwise}
                              \end{cases}`$ |

##### Arctangent

|  |  |  |
|----|----|----|
| **Operation** | `math/atan` | Arctangent function |
| **Input value sockets** | `floatN a` | Tangent value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \pm\frac{\pi}{2} & \text{if } a = \pm\infty \\
                                \arctan(a) \in [-\frac{\pi}{2}; \frac{\pi}{2}] & \text{otherwise}
                              \end{cases}`$ |

> [!NOTE]
> When $`a`$ is infinite, the returned value is an
> implementation-specific approximation of $`\pm\frac{\pi}{2}`$.

##### Arctangent 2

|  |  |  |
|----|----|----|
| **Operation** | `math/atan2` | Arctangent 2 function |
| **Input value sockets** | `floatN a` | Y coordinate |
| `floatN b` | X coordinate |  |
| **Output value sockets** | `floatN value` | Angle between the positive X-axis and the vector from the $`(0, 0)`$ origin to the $`(X, Y)`$ point on a 2D plane; see the description for details |

This function is defined as the **atan2** operation from the
[IEEE-754](#ieee-754) standard including return values for all special
cases.

> [!NOTE]
> This definition also matches the [ECMA-262](#ecma-262) standard so the
> operation is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.atan2(a, b)
> ```

#### Hyperbolic Operations

These all operate component-wise. The description is per component.

If any input value component is *NaN*, the corresponding output value
component is also *NaN*.

##### Hyperbolic Sine

|  |  |  |
|----|----|----|
| **Operation** | `math/sinh` | Hyperbolic sine function |
| **Input value sockets** | `floatN a` | Hyperbolic angle value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \pm\infty & \text{if } a = \pm\infty \\
                                \sinh(a) & \text{otherwise}
                              \end{cases}`$ |

##### Hyperbolic Cosine

|  |  |  |
|----|----|----|
| **Operation** | `math/cosh` | Hyperbolic cosine function |
| **Input value sockets** | `floatN a` | Hyperbolic angle value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                +1 & \text{if } a = \pm0 \\
                                +\infty & \text{if } a = \pm\infty \\
                                \cosh(a) & \text{otherwise}
                              \end{cases}`$ |

##### Hyperbolic Tangent

|  |  |  |
|----|----|----|
| **Operation** | `math/tanh` | Hyperbolic tangent function |
| **Input value sockets** | `floatN a` | Hyperbolic angle value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \pm1 & \text{if } a = \pm\infty \\
                                \tanh(a) & \text{otherwise}
                              \end{cases}`$ |

##### Inverse Hyperbolic Sine

|  |  |  |
|----|----|----|
| **Operation** | `math/asinh` | Inverse hyperbolic sine function |
| **Input value sockets** | `floatN a` | Hyperbolic sine value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \pm\infty & \text{if } a = \pm\infty \\
                                \operatorname{arsinh}(a) & \text{otherwise}
                              \end{cases}`$ |

##### Inverse Hyperbolic Cosine

|  |  |  |
|----|----|----|
| **Operation** | `math/acosh` | Inverse hyperbolic cosine function |
| **Input value sockets** | `floatN a` | Hyperbolic cosine value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \mathit{NaN} & \text{if } a \lt 1 \\
                                +0 & \text{if } a = 1 \\
                                +\infty & \text{if } a = +\infty \\
                                \operatorname{arcosh}(a) & \text{otherwise}
                              \end{cases}`$ |

##### Inverse Hyperbolic Tangent

|  |  |  |
|----|----|----|
| **Operation** | `math/atanh` | Inverse hyperbolic tangent function |
| **Input value sockets** | `floatN a` | Hyperbolic tangent value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \mathit{NaN} & \text{if } |a| \gt 1 \\
                                \pm\infty & \text{if } a = \pm1 \\
                                \pm0 & \text{if } a = \pm0 \\
                                \operatorname{artanh}(a) & \text{otherwise}
                              \end{cases}`$ |

#### Exponential Operations

These all operate component-wise. The description is per component.

If any input value component is *NaN*, the corresponding output value
component is also *NaN* for all operations except `math/pow`.

##### Exponent

|  |  |  |
|----|----|----|
| **Operation** | `math/exp` | Exponent function |
| **Input value sockets** | `floatN a` | Power value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                +0 & \text{if } a = -\infty \\
                                +1 & \text{if } a = \pm0 \\
                                +\infty & \text{if } a = +\infty \\
                                e^a & \text{otherwise}
                              \end{cases}`$ |

##### Natural Logarithm

|  |  |  |
|----|----|----|
| **Operation** | `math/log` | Natural logarithm function |
| **Input value sockets** | `floatN a` | Argument value |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \mathit{NaN} & \text{if } a \lt 0 \\
                                -\infty & \text{if } a = \pm0 \\
                                +0 & \text{if } a = +1 \\
                                +\infty & \text{if } a = +\infty \\
                                \log_e(a) & \text{otherwise}
                              \end{cases}`$ |

##### Base-2 Logarithm

|  |  |  |
|----|----|----|
| **Operation** | `math/log2` | Base-2 logarithm function |
| **Input value sockets** | `floatN a` | Argument |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \mathit{NaN} & \text{if } a \lt 0 \\
                                -\infty & \text{if } a = \pm0 \\
                                +0 & \text{if } a = +1 \\
                                +\infty & \text{if } a = +\infty \\
                                \log_2(a) & \text{otherwise}
                              \end{cases}`$ |

##### Base-10 Logarithm

|  |  |  |
|----|----|----|
| **Operation** | `math/log10` | Base-10 logarithm function |
| **Input value sockets** | `floatN a` | Argument |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \mathit{NaN} & \text{if } a \lt 0 \\
                                -\infty & \text{if } a = \pm0 \\
                                +0 & \text{if } a = +1 \\
                                +\infty & \text{if } a = +\infty \\
                                \log_{10}(a) & \text{otherwise}
                              \end{cases}`$ |

##### Square Root

|  |  |  |
|----|----|----|
| **Operation** | `math/sqrt` | Square root function |
| **Input value sockets** | `floatN a` | Radicand |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \mathit{NaN} & \text{if } a \lt 0 \\
                                \pm0 & \text{if } a = \pm0 \\
                                +\infty & \text{if } a = +\infty \\
                                \sqrt[2]{a} & \text{otherwise}
                              \end{cases}`$ |

##### Cube Root

|  |  |  |
|----|----|----|
| **Operation** | `math/cbrt` | Cube root function |
| **Input value sockets** | `floatN a` | Radicand |
| **Output value sockets** | `floatN value` | $`\begin{cases}
                                \pm0 & \text{if } a = \pm0 \\
                                \pm\infty & \text{if } a = \pm\infty \\
                                \sqrt[3]{a} & \text{otherwise}
                              \end{cases}`$ |

##### Power

|  |  |  |
|----|----|----|
| **Operation** | `math/pow` | Power function |
| **Input value sockets** | `floatN a` | Base |
| `floatN b` | Exponent |  |
| **Output value sockets** | `floatN value` | $`a^b`$; see the description for details |

This function is defined as the **pow** operation from the
[IEEE-754](#ieee-754) standard with the following changes applied:

- $`\mathit{NaN} ^ {\pm0} = 1`$

- $`+1 ^ {\pm\infty}`$, $`-1 ^ {\pm\infty}`$, and
  $`\pm1 ^ \mathit{NaN}`$ are $`\mathit{NaN}`$

> [!NOTE]
> This definition matches the [ECMA-262](#ecma-262) standard so the
> operation is implementable in ECMAScript via the following expression:
>
> ``` js
> a ** b
> ```

#### Vector Operations

See individual operation definitions for handling special floating-point
values.

##### Length

|  |  |  |
|----|----|----|
| **Operation** | `math/length` | Vector length |
| **Input value sockets** | `floatN a` | Vector |
| **Output value sockets** | `float value` | Length of $`a`$, e.g., $`sqrt(a_x^2 + a_y^2)`$ for `float2`; see the description for details |

If any input value component is positive or negative infinity, the
output value is positive infinity.

If none of the input value components are positive or negative infinity
and any input value component is NaN, the output value is NaN.

If all input value components are positive or negative zeros, the output
value is a positive zero.

If all input value components are finite, the output value is an
approximation of the square root of the sum of the input value component
squares.

> [!NOTE]
> This definition matches the **hypot** operation from the
> [IEEE-754](#ieee-754) standard including return values for all special
> cases.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.hypot(...a)
> ```

> [!TIP]
> To get the squared length of $`a`$, use `math/dot` with $`a`$ provided
> to its both input value sockets. Note that this approach will produce
> NaN if any vector component is NaN regardless of other components.

##### Normalize

|  |  |  |
|----|----|----|
| **Operation** | `math/normalize` | Vector normalization |
| **Input value sockets** | `floatN a` | Vector |
| **Output value sockets** | `floatN value` | Vector in the same direction as $`a`$ but with a unit length, e.g., $`\dfrac{\vec{a}}{\sqrt{a_x^2 + a_y^2}}`$ for `float2`; see the description for details |
| `bool isValid` | True if the output vector value has a unit length after normalization; false otherwise |  |

The output values are computed as follows:

1.  Let *length* be the output value of the `math/length` operation on
    $`a`$ as defined above.

2.  If *length* is zero, NaN, or positive infinity, the `isValid` output
    value is false and the `value` output value is a vector of the same
    type as $`a`$ with all components set to positive zeros.

3.  If *length* is a positive finite number, the `isValid` output value
    is true and the `value` output value is a vector of the same type as
    $`a`$ constructed by dividing each component of $`a`$ by *length*.

> [!TIP]
> If the input vector represents a quaternion and the graph expects it
> to be identity in a case when normalization fails, an interactivity
> node with the `math/select` operation could be used to return
> $`(0, 0, 0, 1)`$ when `isValid` is false.

##### Dot Product

|  |  |  |
|----|----|----|
| **Operation** | `math/dot` | Dot product |
| **Input value sockets** | `floatN a` | First vector |
| `floatN b` | Second vector of the same type as $`a`$ |  |
| **Output value sockets** | `float value` | Sum of per-component products of $`a`$ and $`b`$, e.g., $`a_x * b_x + a_y * b_y`$ for `float2` |

Both input value sockets **MUST** have the same type.

Since this operation is a shortcut for the combination of
multiplications and additions, NaN and infinity values are propagated
accordingly.

> [!NOTE]
> This operation is frequently used with both input value sockets
> connected to the same output value socket to compute the squared
> length of a vector.

##### Cross Product

|  |  |  |
|----|----|----|
| **Operation** | `math/cross` | Cross product |
| **Input value sockets** | `float3 a` | Vector |
| `float3 b` | Vector |  |
| **Output value sockets** | `float3 value` | Cross product of $`a`$ and $`b`$, i.e., $`(a_y * b_z - a_z * b_y, a_z * b_x - a_x * b_z, a_x * b_y - a_y * b_x)`$ |

Since this operation is a shortcut for the combination of
multiplications and subtractions, NaN and infinity values are propagated
accordingly.

##### Rotate 2D

|                          |                  |                  |
|--------------------------|------------------|------------------|
| **Operation**            | `math/rotate2D`  | 2D rotation      |
| **Input value sockets**  | `float2 a`       | Vector to rotate |
| `float angle`            | Angle in radians |                  |
| **Output value sockets** | `float2 value`   | Rotated vector   |

Let $`a_x`$ and $`a_y`$ be the components of the `a` input socket value
and $`\alpha`$ be the `angle` input socket value.

Then the components of the `value` output socket value are computed as
follows:

<div class="informalequation">

``` math
x = a_x \cdot \cos(\alpha) - a_y \cdot \sin(\alpha) \\
y = a_x \cdot \sin(\alpha) + a_y \cdot \cos(\alpha)
```

</div>

Since this operation is a shortcut for the combination of trigonometry
and arithmetic operations, NaN and infinity values are propagated
accordingly.

##### Rotate 3D

|                          |                     |                  |
|--------------------------|---------------------|------------------|
| **Operation**            | `math/rotate3D`     | 3D rotation      |
| **Input value sockets**  | `float3 a`          | Vector to rotate |
| `float4 rotation`        | Rotation quaternion |                  |
| **Output value sockets** | `float3 value`      | Rotated vector   |

> [!CAUTION]
> This operation assumes that the rotation quaternion is unit.

Let

- $`\vec{a}`$ be a three-component vector formed from the `a` input
  socket value;

- $`r_x`$, $`r_y`$, $`r_z`$, and $`r_w`$ be the components of the
  `rotation` input socket value;

- $`\vec{r}`$ be a three-component vector formed from $`r_x`$, $`r_y`$,
  and $`r_z`$.

Then the components of the `value` output socket value are computed as
the components of the following vector:

<div class="informalequation">

``` math
\vec{a} + 2 \cdot (\vec{r} \times (\vec{r} \times \vec{a}) + r_w \cdot (\vec{r} \times \vec{a}))
```

</div>

Since this operation is a shortcut for the combination of arithmetic
operations, NaN and infinity values are propagated accordingly.

> [!NOTE]
> This operation is supposed to be more efficient than converting the
> rotation quaternion to a matrix and transforming the vector with it.

> [!TIP]
> This operation does not implicitly normalize the rotation quaternion.
> If needed, that step could be done explicitly by adding an
> interactivity node with the `math/normalize` operation.

##### Transform

|                          |                       |                       |
|--------------------------|-----------------------|-----------------------|
| **Operation**            | `math/transform`      | Vector transformation |
| **Input value sockets**  | `float2 a`            | Vector to transform   |
| `float2x2 b`             | Transformation matrix |                       |
| **Output value sockets** | `float2 value`        | Transformed vector    |

|                          |                       |                       |
|--------------------------|-----------------------|-----------------------|
| **Operation**            | `math/transform`      | Vector transformation |
| **Input value sockets**  | `float3 a`            | Vector to transform   |
| `float3x3 b`             | Transformation matrix |                       |
| **Output value sockets** | `float3 value`        | Transformed vector    |

|                          |                       |                       |
|--------------------------|-----------------------|-----------------------|
| **Operation**            | `math/transform`      | Vector transformation |
| **Input value sockets**  | `float4 a`            | Vector to transform   |
| `float4x4 b`             | Transformation matrix |                       |
| **Output value sockets** | `float4 value`        | Transformed vector    |

##### Vector Spherical Linear Interpolation

|  |  |  |
|----|----|----|
| **Operation** | `math/slerp` | Spherical linear interpolation operation |
| **Input value sockets** | `float2 a` | First vector |
| `float2 b` | Second vector |  |
| `float c` | Unclamped interpolation coefficient |  |
| **Output value sockets** | `float2 value` | Interpolated value |

The `value` output socket value is computed as follows:

1.  Let $`|\vec{a}|`$ be the length of $`\vec{a}`$ and $`|\vec{b}|`$ be
    the length of $`\vec{b}`$.

2.  If $`|\vec{a}|`$ or $`|\vec{b}|`$ are close to zero within an
    implementation-defined threshold,

    1.  set the `value` output to
        $`(1 - c) \cdot \vec{a} + c \cdot \vec{b}`$;

    2.  skip the next steps.

3.  Let $`\hat{a}`$ and $`\hat{b}`$ be the normalized vectors
    $`\vec{a}`$ and $`\vec{b}`$ respectively.

4.  Let $`\theta = \arccos(\hat{a} \cdot \hat{b})`$.

5.  If $`\hat{a}_x \cdot \hat{b}_y − \hat{a}_y \cdot \hat{b}_x`$ is
    negative, negate $`\theta`$.

6.  Let $`L = (1 - c) \cdot |\vec{a}| + c \cdot |\vec{b}|`$.

7.  Set the components of the `value` output socket value using the
    following expressions:

    <div class="informalequation">

    ``` math
    x = (\hat{a}_x \cdot \cos(c \cdot \theta) - \hat{a}_y \cdot \sin(c \cdot \theta)) \cdot L \\
    y = (\hat{a}_x \cdot \sin(c \cdot \theta) + \hat{a}_y \cdot \cos(c \cdot \theta)) \cdot L
    ```

    </div>

Since this operation is a shortcut for the combination of arithmetic and
trigonometry operations, NaN and infinity values are propagated
accordingly.

|  |  |  |
|----|----|----|
| **Operation** | `math/slerp` | Spherical linear interpolation operation |
| **Input value sockets** | `float3 a` | First vector |
| `float3 b` | Second vector |  |
| `float c` | Unclamped interpolation coefficient |  |
| **Output value sockets** | `float3 value` | Interpolated value |

The `value` output socket value is computed as follows:

1.  Let $`|\vec{a}|`$ be the length of $`\vec{a}`$ and $`|\vec{b}|`$ be
    the length of $`\vec{b}`$.

2.  If $`|\vec{a}|`$ or $`|\vec{b}|`$ are close to zero within an
    implementation-defined threshold,

    1.  set the `value` output to
        $`(1 - c) \cdot \vec{a} + c \cdot \vec{b}`$;

    2.  skip the next steps.

3.  Let $`\hat{a}`$ and $`\hat{b}`$ be the normalized vectors
    $`\vec{a}`$ and $`\vec{b}`$ respectively.

4.  Let $`d = \hat{a} \cdot \hat{b}`$.

5.  If $`d`$ is close to positive one within an implementation-defined
    threshold,

    1.  set the `value` output to
        $`(1 - c) \cdot \vec{a} + c \cdot \vec{b}`$;

    2.  skip the next steps.

6.  If $`d`$ is close to negative one within an implementation-defined
    threshold,

    1.  let $`\hat{r}`$ be any unit vector perpendicular to $`\hat{a}`$.

7.  Else,

    1.  let $`\hat{r}`$ be a normalized cross product of $`\hat{a}`$ and
        $`\hat{b}`$.

8.  Let $`Q`$ be a unit quaternion created from the rotation axis of
    $`\hat{r}`$ and the rotation angle of $`c \cdot \arccos(d)`$.

9.  Let $`L = (1 - c) \cdot |\vec{a}| + c \cdot |\vec{b}|`$.

10. Set the `value` output to $`\hat{a}`$ rotated by $`Q`$ and then
    multiplied by $`L`$.

Since this operation is a shortcut for the combination of arithmetic and
trigonometry operations, NaN and infinity values are propagated
accordingly.

#### Matrix Operations

##### Transpose

|  |  |  |
|----|----|----|
| **Operation** | `math/transpose` | Transpose operation |
| **Input value sockets** | `floatNxN a` | Matrix to transpose |
| **Output value sockets** | `floatNxN value` | Matrix that is the transpose of $`a`$ |

The input and output value sockets have the same type.

This operation only reorders the matrix elements without inspecting or
altering their values.

##### Determinant

|                          |                    |                      |
|--------------------------|--------------------|----------------------|
| **Operation**            | `math/determinant` | Dot product          |
| **Input value sockets**  | `floatNxN a`       | Matrix               |
| **Output value sockets** | `float value`      | Determinant of $`a`$ |

Since this operation is a shortcut for the combination of
multiplications, subtractions, and additions, NaN and infinity values
are propagated accordingly.

##### Inverse

|  |  |  |
|----|----|----|
| **Operation** | `math/inverse` | Inverse operation |
| **Input value sockets** | `floatNxN a` | Matrix $`A`$ to inverse |
| **Output value sockets** | `floatNxN value` | Matrix that is the inverse of $`A`$; see the description for details |
| `bool isValid` | True if the input matrix is invertible; false otherwise |  |

The `value` input value socket and `value` output value socket have the
same type.

The output values are computed as follows:

1.  Let *determinant* be the output value of the `math/determinant`
    operation on $`A`$ as defined above.

2.  If *determinant* is zero, NaN, or infinity, the `isValid` output
    value is false and the `value` output value is a matrix of the same
    type as $`A`$ with all elements set to positive zeros.

3.  If *determinant* is a finite number not equal to zero, the `isValid`
    output value is true and the `value` output value is a matrix that
    is an implementation-defined approximation of the inverse of $`A`$.

##### Multiplication

|                          |                  |                                 |
|--------------------------|------------------|---------------------------------|
| **Operation**            | `math/matMul`    | Matrix multiplication operation |
| **Input value sockets**  | `floatNxN a`     | First matrix                    |
| `floatNxN b`             | Second matrix    |                                 |
| **Output value sockets** | `floatNxN value` | Matrix product                  |

Both input value sockets **MUST** have the same type.

The output value socket has the same type as the input value sockets.

Since this operation is a shortcut for the combination of
multiplications and additions, NaN and infinity values are propagated
accordingly.

> [!NOTE]
> See `math/mul` for per-element multiplication.

##### Compose

|  |  |  |
|----|----|----|
| **Operation** | `math/matCompose` | Compose a 4x4 transform matrix |
| **Input value sockets** | `float3 translation` | Translation vector |
| `float4 rotation` | Rotation quaternion |  |
| `float3 scale` | Scale vector |  |
| **Output value sockets** | `float4x4 value` | Matrix composed from the TRS properties |

> [!CAUTION]
> This operation assumes that the rotation quaternion is unit.

Let

- $`t_x`$, $`t_y`$, and $`t_z`$ be the translation vector components;

- $`r_x`$, $`r_y`$, $`r_z`$, and $`r_w`$ be the rotation quaternion
  components;

- $`s_x`$, $`s_y`$, and $`s_z`$ be the scale vector components.

Then the `value` output socket value is computed as follows:

<div class="informalequation">

``` math
((1, 0, 0, t_x),
 (0, 1, 0, t_y),
 (0, 0, 1, t_z),
 (0, 0, 0, 1)) cdot
((1 - 2(r_y^2 + r_z^2), 2(r_xr_y - r_zr_w),   2(r_xr_z + r_yr_w),   0),
 (2(r_xr_y + r_zr_w),   1 - 2(r_x^2 + r_z^2), 2(r_yr_z - r_xr_w),   0),
 (2(r_xr_z - r_yr_w),   2(r_yr_z + r_xr_w),   1 - 2(r_x^2 + r_y^2), 0),
 (0, 0, 0, 1)) cdot
((s_x, 0,   0,   0),
 (0,   s_y, 0,   0),
 (0,   0,   s_z, 0),
 (0,   0,   0,   1)) =

= ((s_x * (1 - 2(r_y^2 + r_z^2)), s_y * 2(r_xr_y - r_zr_w),     s_z * 2(r_xr_z + r_yr_w),     t_x),
   (s_x * 2(r_xr_y + r_zr_w),     s_y * (1 - 2(r_x^2 + r_z^2)), s_z * 2(r_yr_z - r_xr_w),     t_y),
   (s_x * 2(r_xr_z - r_yr_w),     s_y * 2(r_yr_z + r_xr_w),     s_z * (1 - 2(r_x^2 + r_y^2)), t_z),
   (0, 0, 0, 1))
```

</div>

Since this operation is a shortcut for the combination of
multiplications, subtractions, and additions, NaN and infinity values
are propagated accordingly.

> [!TIP]
> This operation does not implicitly normalize the rotation quaternion.
> If needed, that step could be done explicitly by adding an
> interactivity node with the `math/normalize` operation.

##### Decompose

|  |  |  |
|----|----|----|
| **Operation** | `math/matDecompose` | Decompose a 4x4 transform matrix to TRS properties |
| **Input value sockets** | `float4x4 a` | Matrix $`A`$ to decompose |
| **Output value sockets** | `float3 translation` | Translation vector |
| `float4 rotation` | Rotation quaternion |  |
| `float3 scale` | Scale vector |  |

> [!CAUTION]
> This operation is intended for matrices produced by the
> `math/matCompose` operation, their products, and inverses. It may not
> be suitable for decomposing arbitrary transforms not typically used in
> glTF assets.

The output values are computed as follows:

1.  The first three elements of the fourth row of $`A`$ are assumed to
    be zeros and the last element of the fourth row of $`A`$ is assumed
    to be close to positive one. The following steps ignore actual
    values present there.

2.  Set the `translation` output value to the first three elements of
    the fourth column of $`A`$, i.e., to $`(a_{14}, a_{24}, a_{34})`$.

3.  Let $`s_x`$, $`s_y`$, and $`s_z`$ be lengths of the first three
    columns of $`A`$. For example,
    $`s_x=sqrt(a_{11}^2+a_{21}^2+a_{31}^2)`$.

4.  If $`s_x`$, $`s_y`$, or $`s_z`$ are infinite, NaN, or equal to zero,

    1.  set the `scale` output value to $`(s_x, s_y, s_z)`$;

    2.  set the `rotation` output value to an identity quaternion, i.e.,
        to $`(0, 0, 0, \pm1)`$;

    3.  skip the next steps.

5.  Let $`B`$ be a 3x3 matrix formed by taking the upper-left 3x3
    sub-matrix of $`A`$ and dividing each column by $`s_x`$, $`s_y`$,
    and $`s_z`$ respectively.

    <div class="informalequation">

    ``` math
    B = ((a_{11}/s_x, a_{12}/s_y, a_{13}/s_z),
         (a_{21}/s_x, a_{22}/s_y, a_{23}/s_z),
         (a_{31}/s_x, a_{32}/s_y, a_{33}/s_z))
    ```

    </div>

6.  If the absolute value of the determinant of $`B`$ is not close to
    one within an implementation-defined threshold, the matrix contains
    shear and thus it is not generally decomposable into rotation and
    scale components. It is up to implementations whether to extract and
    remove the shear component prior to the next steps or proceed as is.
    In either case, recombining the resulting rotation and scale
    components will not produce the original matrix.

7.  If the determinant of $`B`$ is positive, set the `scale` output
    value to $`(s_x, s_y, s_z)`$.

8.  If the determinant of $`B`$ is negative, do one of the following
    four options.

    1.  First option:

        1.  set the `scale` output value to $`(-s_x, s_y, s_z)`$;

        2.  negate elements of the first column of $`B`$ in-place.

    2.  Second option:

        1.  set the `scale` output value to $`(s_x, -s_y, s_z)`$;

        2.  negate elements of the second column of $`B`$ in-place.

    3.  Third option:

        1.  set the `scale` output value to $`(s_x, s_y, -s_z)`$;

        2.  negate elements of the third column of $`B`$ in-place.

    4.  Fourth option:

        1.  set the `scale` output value to $`(-s_x, -s_y, -s_z)`$;

        2.  negate all elements of $`B`$ in-place.

9.  Set the `rotation` output value to the unit quaternion corresponding
    to the rotation matrix $`B`$.

#### Quaternion Operations

##### Conjugation

|  |  |  |
|----|----|----|
| **Operation** | `math/quatConjugate` | Quaternion conjugation operation |
| **Input value sockets** | `float4 a` | Input quaternion |
| **Output value sockets** | `float4 value` | Conjugated quaternion |

Let $`a_x`$, $`a_y`$, $`a_z`$, and $`a_w`$ be the components of $`a`$.

Then the components of the `value` output socket value are set as
follows:

<div class="informalequation">

``` math
x = -a_x \\
y = -a_y \\
z = -a_z \\
w = a_w
```

</div>

Since this operation is a shortcut for the combination of negations, NaN
and infinity values are propagated accordingly.

> [!TIP]
> If the quaternion is unit, this operation also produces the
> quaternion’s inverse.

##### Multiplication

|  |  |  |
|----|----|----|
| **Operation** | `math/quatMul` | Quaternion multiplication operation |
| **Input value sockets** | `float4 a` | First quaternion |
| `float4 b` | Second quaternion |  |
| **Output value sockets** | `float4 value` | Quaternion product |

Let

- $`a_x`$, $`a_y`$, $`a_z`$, and $`a_w`$ be the components of $`a`$;

- $`b_x`$, $`b_y`$, $`b_z`$, and $`b_w`$ be the components of $`b`$.

Then the components of the `value` output socket value are computed as
follows:

<div class="informalequation">

``` math
x = a_w * b_x + a_x * b_w + a_y * b_z - a_z * b_y \
y = a_w * b_y + a_y * b_w + a_z * b_x - a_x * b_z \
z = a_w * b_z + a_z * b_w + a_x * b_y - a_y * b_x \
w = a_w * b_w - a_x * b_x - a_y * b_y - a_z * b_z
```

</div>

Since this operation is a shortcut for the combination of
multiplications, subtractions, and additions, NaN and infinity values
are propagated accordingly.

##### Angle Between Quaternions

|  |  |  |
|----|----|----|
| **Operation** | `math/quatAngleBetween` | Angle between two quaternions |
| **Input value sockets** | `float4 a` | First quaternion |
| `float4 b` | Second quaternion |  |
| **Output value sockets** | `float value` | Angle in radians |

> [!CAUTION]
> This operation assumes that both input quaternions are unit.

Let

- $`a_x`$, $`a_y`$, $`a_z`$, and $`a_w`$ be the components of $`a`$;

- $`b_x`$, $`b_y`$, $`b_z`$, and $`b_w`$ be the components of $`b`$.

Then the `value` output socket value is computed as follows:

<div class="informalequation">

``` math
2 \cdot \arccos(a_x \cdot b_x + a_y \cdot b_y + a_z \cdot b_z + a_w \cdot b_w)
```

</div>

Since this operation is a shortcut for the combination of arithmetic and
trigonometry operations, NaN and infinity values are propagated
accordingly.

> [!TIP]
> This operation does not implicitly normalize the input quaternions. If
> needed, that step could be done explicitly by adding interactivity
> nodes with the `math/normalize` operation.

##### Quaternion From Axis & Angle

|  |  |  |
|----|----|----|
| **Operation** | `math/quatFromAxisAngle` | Create a quaternion from a rotation axis and an angle |
| **Input value sockets** | `float3 axis` | Rotation axis |
| `float angle` | Angle in radians |  |
| **Output value sockets** | `float4 value` | Rotation quaternion |

> [!CAUTION]
> This operation assumes that the rotation axis vector is unit.

The components of the `value` output socket value are computed as
follows:

<div class="informalequation">

``` math
x = \textit{axis}_x \cdot \sin(0.5 \cdot \textit{angle}) \\
y = \textit{axis}_y \cdot \sin(0.5 \cdot \textit{angle}) \\
z = \textit{axis}_z \cdot \sin(0.5 \cdot \textit{angle}) \\
w = \cos(0.5 \cdot \textit{angle})
```

</div>

Since this operation is a shortcut for the combination of
multiplications and trigonometry functions, NaN and infinity values are
propagated accordingly.

> [!TIP]
> This operation does not implicitly normalize the rotation axis vector.
> If needed, that step could be done explicitly by adding an
> interactivity node with the `math/normalize` operation.

##### Quaternion To Axis & Angle

|  |  |  |
|----|----|----|
| **Operation** | `math/quatToAxisAngle` | Decompose a quaternion to a rotation axis and an angle |
| **Input value sockets** | `float4 a` | Rotation quaternion |
| **Output value sockets** | `float3 axis` | Rotation axis |
| `float angle` | Angle in radians |  |

> [!CAUTION]
> This operation assumes that the rotation quaternion is unit.

Let $`a_x`$, $`a_y`$, $`a_z`$, and $`a_w`$ be the components of $`a`$.

Then the `angle` and `axis` output socket values are computed as
follows:

1.  If the absolute value of $`a_w`$ is close to one within an
    implementation-defined threshold, set the `angle` socket value to
    zero and the `axis` socket value to any axis-aligned unit vector,
    i.e., to one of $`(\pm1, 0, 0)`$, $`(0, \pm1, 0)`$, or
    $`(0, 0, \pm1)`$.

2.  Else set `angle` and `axis` socket values using the following
    expressions:

    <div class="informalequation">

    ``` math
    \textit{axis}_x = \frac{a_x}{\sqrt{1 - a^2_w}} \\
    \textit{axis}_y = \frac{a_y}{\sqrt{1 - a^2_w}} \\
    \textit{axis}_z = \frac{a_z}{\sqrt{1 - a^2_w}} \\
    \textit{angle} = 2 \cdot \arccos(a_w)
    ```

    </div>

Since this operation is a shortcut for the combination of arithmetic and
trigonometry functions, NaN and infinity values are propagated
accordingly.

> [!TIP]
> This operation does not implicitly normalize the rotation quaternion.
> If needed, that step could be done explicitly by adding an
> interactivity node with the `math/normalize` operation.

##### Quaternion From Two Directional Vectors

|  |  |  |
|----|----|----|
| **Operation** | `math/quatFromDirections` | Create a quaternion transforming one directional vector to another |
| **Input value sockets** | `float3 a` | First direction |
| `float3 b` | Second direction |  |
| **Output value sockets** | `float4 value` | Rotation quaternion |

> [!CAUTION]
> This operation assumes that both directions are unit.

The components of the `value` output socket value are computed as
follows:

1.  Let $`c`$ be the dot product of $`\vec{a}`$ and $`\vec{b}`$.

2.  If $`c`$ is close to positive one within an implementation-defined
    threshold,

    1.  set the `value` output value to an identity quaternion, i.e.,
        set the $`w`$ component of the `value` output value to $`\pm1`$
        and set the other three components to zeros;

    2.  skip the next steps.

3.  If $`c`$ is close to negative one within an implementation-defined
    threshold,

    1.  set the $`x`$, $`y`$, and $`z`$ components of the `value` output
        socket value to the corresponding components of a unit vector
        representing a direction perpendicular to $`\vec{a}`$;

    2.  set the $`w`$ component of the `value` output socket value to
        zero;

    3.  skip the next steps.

4.  Let $`\vec{r}`$ be the normalized cross product of $`\vec{a}`$ and
    $`\vec{b}`$.

5.  Set the components of the `value` output socket value using the
    following expressions:

    <div class="informalequation">

    ``` math
    x = r_x \cdot \sqrt{0.5 - 0.5 \cdot c} \\
    y = r_y \cdot \sqrt{0.5 - 0.5 \cdot c} \\
    z = r_z \cdot \sqrt{0.5 - 0.5 \cdot c} \\
    w = \sqrt{0.5 + 0.5 \cdot c}
    ```

    </div>

Since this operation is a shortcut for the combination of arithmetic and
exponential functions, NaN and infinity values are propagated
accordingly.

> [!TIP]
> This operation implies that both input vectors are normalized.
> Interactivity nodes with the `math/normalize` operation could be added
> to handle non-normalized inputs.

##### Quaternion From Up and Forward Directional Vectors

|  |  |  |
|----|----|----|
| **Operation** | `math/quatFromUpForward` | Create a quaternion from the specified up and forward directions |
| **Input value sockets** | `float3 up` | Up direction |
| `float3 forward` | Forward direction |  |
| **Output value sockets** | `float4 value` | Rotation quaternion |

> [!CAUTION]
> This operation assumes that both input directions are unit.

The `value` output socket value is computed as follows:

1.  Let $`\vec{y}`$ be a three-component vector corresponding to the
    `up` input socket value and $`\vec{r}`$ be a three-component vector
    corresponding to the `forward` input socket value.

2.  If $`\vec{y}`$ and $`\vec{r}`$ are colinear within an
    implementation-defined threshold,

    1.  let $`\vec{s}`$ be a three-component unit vector representing a
        direction perpendicular to $`\vec{r}`$.

3.  Else

    1.  let $`\vec{s}`$ be the normalized cross product of $`\vec{y}`$
        and $`\vec{r}`$.

4.  Let $`\vec{t}`$ be the cross product of $`\vec{r}`$ and $`\vec{s}`$.

5.  Let $`M`$ be a rotation matrix composed as follows:

    <div class="informalequation">

    ``` math
    M = ((s_x, t_x, r_x),
         (s_y, t_y, r_y),
         (s_z, t_z, r_z))
    ```

    </div>

6.  Set the `value` output value to the unit quaternion corresponding to
    the rotation matrix $`M`$.

> [!TIP]
> This operation implies that both input vectors are normalized.
> Interactivity nodes with the `math/normalize` operation could be added
> to handle non-normalized inputs.

##### Quaternion From Three Angles

|  |  |  |
|----|----|----|
| **Operation** | `math/quatFromAngles` | Create a quaternion from the specified angles |
| **Configuration** | `string order` | The rotation order; `yxz` in the default configuration |
| **Input value sockets** | `float x` | Rotation around X in radians |
| `float y` | Rotation around Y in radians |  |
| `float z` | Rotation around Z in radians |  |
| **Output value sockets** | `float4 value` | Rotation quaternion |

In the default configuration, the `order` configuration value is `yxz`.

If the `order` configuration property is not provided by the behavior
graph, if it is not a literal string, if its value is not exactly one of
`xyz`, `xzy`, `yxz`, `yzx`, `zxy`, or `zyx`, the default configuration
**MUST** be used.

The input values represent Tait–Bryan intrinsic angles.

The output value is a unit quaternion representing the rotation produced
by applying the angles in the order specified by the configuration.

Since this operation is a shortcut for the combination of arithmetic and
trigonometry functions, NaN and infinity values are propagated
accordingly.

##### Quaternion Spherical Linear Interpolation

|  |  |  |
|----|----|----|
| **Operation** | `math/quatSlerp` | Spherical linear interpolation operation |
| **Input value sockets** | `float4 a` | First quaternion |
| `float4 b` | Second quaternion |  |
| `float c` | Unclamped interpolation coefficient |  |
| **Output value sockets** | `float4 value` | Interpolated value |

> [!CAUTION]
> This operation assumes that both input quaternions are unit.

The `value` output socket value is computed as follows:

1.  Let

    1.  $`a_x`$, $`a_y`$, $`a_z`$, and $`a_w`$ be the components of
        $`a`$;

    2.  $`b_x`$, $`b_y`$, $`b_z`$, and $`b_w`$ be the components of
        $`b`$.

2.  Let
    $`d = a_x \cdot b_x + a_y \cdot b_y + a_z \cdot b_z + a_w \cdot b_w`$.

3.  If $`d`$ is negative,

    1.  set $`d`$ to $`-d`$;

    2.  negate all components of the quaternion $`b`$.

4.  If $`d`$ is close to positive one within an implementation-defined
    threshold,

    1.  let $`k_a = 1 - c`$, $`k_b = c`$.

5.  Else let:

    1.  $`\omega = \arccos(d)`$;

    2.  $`k_a = \frac{\sin(\omega \cdot (1 - c))}{\sin(\omega)}`$,
        $`k_b = \frac{\sin(\omega \cdot c)}{\sin(\omega)}`$.

6.  Set the components of the `value` output socket value using the
    following expressions:

    <div class="informalequation">

    ``` math
    x = a_x \cdot k_a + b_x \cdot k_b \\
    y = a_y \cdot k_a + b_y \cdot k_b \\
    z = a_z \cdot k_a + b_z \cdot k_b \\
    w = a_w \cdot k_a + b_w \cdot k_b
    ```

    </div>

Since this operation is a shortcut for the combination of arithmetic and
trigonometry operations, NaN and infinity values are propagated
accordingly.

> [!TIP]
> This operation does not implicitly normalize the input quaternions. If
> needed, that step could be done explicitly by adding interactivity
> nodes with the `math/normalize` operation.

#### Swizzle Operations

##### Combine

|  |  |  |
|----|----|----|
| **Operation** | `math/combine2` | Combine two floats into a two-component vector |
| **Input value sockets** | `float a` | First component |
| `float b` | Second component |  |
| **Output value sockets** | `float2 value` | Vector |

|  |  |  |
|----|----|----|
| **Operation** | `math/combine3` | Combine three floats into a three-component vector |
| **Input value sockets** | `float a` | First component |
| `float b` | Second component |  |
| `float c` | Third component |  |
| **Output value sockets** | `float3 value` | Vector |

|  |  |  |
|----|----|----|
| **Operation** | `math/combine4` | Combine four floats into a four-component vector |
| **Input value sockets** | `float a` | First component |
| `float b` | Second component |  |
| `float c` | Third component |  |
| `float d` | Fourth component |  |
| **Output value sockets** | `float4 value` | Vector |

|  |  |  |
|----|----|----|
| **Operation** | `math/combine2x2` | Combine 4 floats into a 2x2 matrix |
| **Input value sockets** | `float a` | First row, first column element |
| `float b` | Second row, first column element |  |
| `float c` | First row, second column element |  |
| `float d` | Second row, second column element |  |
| **Output value sockets** | `float2x2 value` | Matrix |

|  |  |  |
|----|----|----|
| **Operation** | `math/combine3x3` | Combine 9 floats into a 3x3 matrix |
| **Input value sockets** | `float a` | First row, first column element |
| `float b` | Second row, first column element |  |
| `float c` | Third row, first column element |  |
| `float d` | First row, second column element |  |
| `float e` | Second row, second column element |  |
| `float f` | Third row, second column element |  |
| `float g` | First row, third column element |  |
| `float h` | Second row, third column element |  |
| `float i` | Third row, third column element |  |
| **Output value sockets** | `float3x3 value` | Matrix |

|  |  |  |
|----|----|----|
| **Operation** | `math/combine4x4` | Combine 16 floats into a 4x4 matrix |
| **Input value sockets** | `float a` | First row, first column element |
| `float b` | Second row, first column element |  |
| `float c` | Third row, first column element |  |
| `float d` | Fourth row, first column element |  |
| `float e` | First row, second column element |  |
| `float f` | Second row, second column element |  |
| `float g` | Third row, second column element |  |
| `float h` | Fourth row, second column element |  |
| `float i` | First row, third column element |  |
| `float j` | Second row, third column element |  |
| `float k` | Third row, third column element |  |
| `float l` | Fourth row, third column element |  |
| `float m` | First row, fourth column element |  |
| `float n` | Second row, fourth column element |  |
| `float o` | Third row, fourth column element |  |
| `float p` | Fourth row, fourth column element |  |
| **Output value sockets** | `float4x4 value` | Matrix |

##### Extract

|  |  |  |
|----|----|----|
| **Operation** | `math/extract2` | Extract two floats from a two-component vector |
| **Input value sockets** | `float2 a` | Vector |
| **Output value sockets** | `float 0` | First component |
| `float 1` | Second component |  |

|  |  |  |
|----|----|----|
| **Operation** | `math/extract3` | Extract three floats from a three-component vector |
| **Input value sockets** | `float3 a` | Vector |
| **Output value sockets** | `float 0` | First component |
| `float 1` | Second component |  |
| `float 2` | Third component |  |

|  |  |  |
|----|----|----|
| **Operation** | `math/extract4` | Extract four floats from a four-component vector |
| **Input value sockets** | `float4 a` | Vector |
| **Output value sockets** | `float 0` | First component |
| `float 1` | Second component |  |
| `float 2` | Third component |  |
| `float 3` | Fourth component |  |

|  |  |  |
|----|----|----|
| **Operation** | `math/extract2x2` | Extract 4 floats from a 2x2 matrix |
| **Input value sockets** | `float2x2 a` | Matrix |
| **Output value sockets** | `float 0` | First row, first column element |
| `float 1` | Second row, first column element |  |
| `float 2` | First row, second column element |  |
| `float 3` | Second row, second column element |  |

|  |  |  |
|----|----|----|
| **Operation** | `math/extract3x3` | Extract 9 floats from a 3x3 matrix |
| **Input value sockets** | `float3x3 a` | Matrix |
| **Output value sockets** | `float 0` | First row, first column element |
| `float 1` | Second row, first column element |  |
| `float 2` | Third row, first column element |  |
| `float 3` | First row, second column element |  |
| `float 4` | Second row, second column element |  |
| `float 5` | Third row, second column element |  |
| `float 6` | First row, third column element |  |
| `float 7` | Second row, third column element |  |
| `float 8` | Third row, third column element |  |

|  |  |  |
|----|----|----|
| **Operation** | `math/extract4x4` | Extract 16 floats from a 4x4 matrix |
| **Input value sockets** | `float4x4 a` | Matrix |
| **Output value sockets** | `float 0` | First row, first column element |
| `float 1` | Second row, first column element |  |
| `float 2` | Third row, first column element |  |
| `float 3` | Fourth row, first column element |  |
| `float 4` | First row, second column element |  |
| `float 5` | Second row, second column element |  |
| `float 6` | Third row, second column element |  |
| `float 7` | Fourth row, second column element |  |
| `float 8` | First row, third column element |  |
| `float 9` | Second row, third column element |  |
| `float 10` | Third row, third column element |  |
| `float 11` | Fourth row, third column element |  |
| `float 12` | First row, fourth column element |  |
| `float 13` | Second row, fourth column element |  |
| `float 14` | Third row, fourth column element |  |
| `float 15` | Fourth row, fourth column element |  |

#### Integer Arithmetic Operations

All inputs to these operations are two’s complement 32-bit signed
integers.

##### Absolute Value

|  |  |  |
|----|----|----|
| **Operation** | `math/abs` | Absolute value operation |
| **Input value sockets** | `int a` | Argument |
| **Output value sockets** | `int value` | $`\begin{cases}
                             -a & \text{if } a \lt 0 \\
                              a & \text{if } a \ge 0
                           \end{cases}`$ |

As this operation is defined in terms of the negation operation (see
below), the absolute value of `-2147483648` is `-2147483648`.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.abs(a) | 0
> ```

##### Sign

|  |  |  |
|----|----|----|
| **Operation** | `math/sign` | Sign operation |
| **Input value sockets** | `int a` | Argument |
| **Output value sockets** | `int value` | $`\begin{cases}
                             -1 & \text{if } a \lt 0 \\
                              0 & \text{if } a = 0 \\
                             +1 & \text{if } a \gt 0
                           \end{cases}`$ |

##### Negation

|                          |             |                    |
|--------------------------|-------------|--------------------|
| **Operation**            | `math/neg`  | Negation operation |
| **Input value sockets**  | `int a`     | Argument           |
| **Output value sockets** | `int value` | $`-a`$             |

Negating `-2147483648` **MUST** return `-2147483648`.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> (-a) | 0
> ```

##### Addition

|                          |               |                    |
|--------------------------|---------------|--------------------|
| **Operation**            | `math/add`    | Addition operation |
| **Input value sockets**  | `int a`       | First addend       |
| `int b`                  | Second addend |                    |
| **Output value sockets** | `int value`   | Sum, $`a + b`$     |

Arithmetic overflow **MUST** wrap around, for example:

    2147483647 + 1 == -2147483648

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> (a + b) | 0
> ```

##### Subtraction

|                          |             |                       |
|--------------------------|-------------|-----------------------|
| **Operation**            | `math/sub`  | Subtraction operation |
| **Input value sockets**  | `int a`     | Minuend               |
| `int b`                  | Subtrahend  |                       |
| **Output value sockets** | `int value` | Difference, $`a - b`$ |

Arithmetic overflow **MUST** wrap around, for example:

    -2147483648 - 1 == 2147483647

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> (a - b) | 0
> ```

##### Multiplication

|                          |               |                          |
|--------------------------|---------------|--------------------------|
| **Operation**            | `math/mul`    | Multiplication operation |
| **Input value sockets**  | `int a`       | First factor             |
| `int b`                  | Second factor |                          |
| **Output value sockets** | `int value`   | Product, $`a * b`$       |

Arithmetic overflow **MUST** wrap around, for example:

     2147483647 * 2147483647 == 1

    -2147483648 * (-1)       == -2147483648

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.imul(a, b)
> ```

##### Division

|  |  |  |
|----|----|----|
| **Operation** | `math/div` | Division operation |
| **Input value sockets** | `int a` | Dividend |
| `int b` | Divisor |  |
| **Output value sockets** | `int value` | $`\begin{cases}
                             \frac{a}{b} & \text{if } b \ne 0 \\
                             0 & \text{if } b = 0
                           \end{cases}`$ |

The quotient **MUST** be truncated towards zero.

Arithmetic overflow is defined as follows:

    -2147483648 / (-1) == -2147483648

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> (a / b) | 0
> ```

##### Remainder

|  |  |  |
|----|----|----|
| **Operation** | `math/rem` | Remainder operation |
| **Input value sockets** | `int a` | Dividend |
| `int b` | Divisor |  |
| **Output value sockets** | `int value` | $`\begin{cases}
                             a - (b \cdot \operatorname{trunc}(\frac{a}{b})) & \text{if } b \ne 0 \\
                             0 & \text{if } b = 0
                           \end{cases}`$ |

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> (a % b) | 0
> ```

##### Minimum

|                          |                 |                           |
|--------------------------|-----------------|---------------------------|
| **Operation**            | `math/min`      | Minimum operation         |
| **Input value sockets**  | `int a`         | First argument            |
| `int b`                  | Second argument |                           |
| **Output value sockets** | `int value`     | Smallest of the arguments |

##### Maximum

|                          |                 |                          |
|--------------------------|-----------------|--------------------------|
| **Operation**            | `math/max`      | Maximum operation        |
| **Input value sockets**  | `int a`         | First argument           |
| `int b`                  | Second argument |                          |
| **Output value sockets** | `int value`     | Largest of the arguments |

##### Clamp

|  |  |  |
|----|----|----|
| **Operation** | `math/clamp` | Clamp operation |
| **Input value sockets** | `int a` | Value to clamp |
| `int b` | First boundary |  |
| `int c` | Second boundary |  |
| **Output value sockets** | `int value` | $`\min(\max(a, \min(b, c)), \max(b, c))`$ |

This operation is defined in terms of `math/min` and `math/max`
operations defined above.

> [!NOTE]
> This operation correctly handles a case when $`b`$ is greater than
> $`c`$.

#### Integer Comparison Operations

All inputs to these operations are two’s complement 32-bit signed
integers.

##### Equality

|  |  |  |
|----|----|----|
| **Operation** | `math/eq` | Equality operation |
| **Input value sockets** | `int a` | First argument |
| `int b` | Second argument |  |
| **Output value sockets** | `bool value` | True if the input arguments are equal; false otherwise |

##### Less Than

|  |  |  |
|----|----|----|
| **Operation** | `math/lt` | Less than operation |
| **Input value sockets** | `int a` | First argument |
| `int b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a < b`$; false otherwise |

##### Less Than Or Equal To

|  |  |  |
|----|----|----|
| **Operation** | `math/le` | Less than or equal to operation |
| **Input value sockets** | `int a` | First argument |
| `int b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a <= b`$; false otherwise |

##### Greater Than

|  |  |  |
|----|----|----|
| **Operation** | `math/gt` | Greater than operation |
| **Input value sockets** | `int a` | First argument |
| `int b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a > b`$; false otherwise |

##### Greater Than Or Equal To

|  |  |  |
|----|----|----|
| **Operation** | `math/ge` | Greater than or equal operation |
| **Input value sockets** | `int a` | First argument |
| `int b` | Second argument |  |
| **Output value sockets** | `bool value` | True if $`a >= b`$; false otherwise |

#### Integer Bitwise Operations

All inputs to these operations are two’s complement 32-bit signed
integers.

##### Bitwise NOT

|                          |             |                       |
|--------------------------|-------------|-----------------------|
| **Operation**            | `math/not`  | Bitwise NOT operation |
| **Input value sockets**  | `int a`     | Argument              |
| **Output value sockets** | `int value` | `~a`                  |

##### Bitwise AND

|                          |                 |                       |
|--------------------------|-----------------|-----------------------|
| **Operation**            | `math/and`      | Bitwise AND operation |
| **Input value sockets**  | `int a`         | First argument        |
| `int b`                  | Second argument |                       |
| **Output value sockets** | `int value`     | `a & b`               |

##### Bitwise OR

|                          |                 |                      |
|--------------------------|-----------------|----------------------|
| **Operation**            | `math/or`       | Bitwise OR operation |
| **Input value sockets**  | `int a`         | First argument       |
| `int b`                  | Second argument |                      |
| **Output value sockets** | `int value`     | `a | b`              |

##### Bitwise XOR

|                          |                 |                       |
|--------------------------|-----------------|-----------------------|
| **Operation**            | `math/xor`      | Bitwise XOR operation |
| **Input value sockets**  | `int a`         | First argument        |
| `int b`                  | Second argument |                       |
| **Output value sockets** | `int value`     | `a ^ b`               |

##### Right Shift

|                          |                            |                     |
|--------------------------|----------------------------|---------------------|
| **Operation**            | `math/asr`                 | Right Shift         |
| **Input value sockets**  | `int a`                    | Value to be shifted |
| `int b`                  | Number of bits to shift by |                     |
| **Output value sockets** | `int value`                | `a >> b`            |

Only the lowest 5 bits of $`b`$ are considered, i.e., its effective
range is \[0, 31\]. The result **MUST** be truncated to 32 bits and
interpreted as a two’s complement signed integer. The most significant
bit of $`a`$ **MUST** be propagated.

##### Left Shift

|                          |                            |                     |
|--------------------------|----------------------------|---------------------|
| **Operation**            | `math/lsl`                 | Left Shift          |
| **Input value sockets**  | `int a`                    | Value to be shifted |
| `int b`                  | Number of bits to shift by |                     |
| **Output value sockets** | `int value`                | `a << b`            |

Only the lowest 5 bits of $`b`$ are considered, i.e., its effective
range is \[0, 31\]. The result **MUST** be truncated to 32 bits and
interpreted as a two’s complement signed integer.

##### Count Leading Zeros

|                          |             |                                      |
|--------------------------|-------------|--------------------------------------|
| **Operation**            | `math/clz`  | Count leading zeros operation        |
| **Input value sockets**  | `int a`     | Argument                             |
| **Output value sockets** | `int value` | Number of leading zero bits in $`a`$ |

If $`a`$ is 0, the operation returns 32; if $`a`$ is negative, the
operation returns 0.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> Math.clz32(a)
> ```

##### Count Trailing Zeros

|                          |             |                                       |
|--------------------------|-------------|---------------------------------------|
| **Operation**            | `math/ctz`  | Count trailing zeros operation        |
| **Input value sockets**  | `int a`     | Argument                              |
| **Output value sockets** | `int value` | Number of trailing zero bits in $`a`$ |

If $`a`$ is 0, the operation returns 32.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> a ? (31 - Math.clz32(a & -a)) : 32
> ```

##### Count One Bits

|                          |               |                             |
|--------------------------|---------------|-----------------------------|
| **Operation**            | `math/popcnt` | Count set bits operation    |
| **Input value sockets**  | `int a`       | Argument                    |
| **Output value sockets** | `int value`   | Number of set bits in $`a`$ |

If $`a`$ is 0, the operation returns 0; if $`a`$ is -1, the operation
returns 32.

#### Boolean Arithmetic Operations

##### Equality

|  |  |  |
|----|----|----|
| **Operation** | `math/eq` | Equality operation |
| **Input value sockets** | `bool a` | First argument |
| `bool b` | Second argument |  |
| **Output value sockets** | `bool value` | True if and only if both $`a`$ and $`b`$ have the same value; false otherwise |

##### Boolean NOT

|  |  |  |
|----|----|----|
| **Operation** | `math/not` | Boolean NOT operation |
| **Input value sockets** | `bool a` | Argument |
| **Output value sockets** | `bool value` | True if $`a`$ is false; false if $`a`$ is true |

##### Boolean AND

|  |  |  |
|----|----|----|
| **Operation** | `math/and` | Boolean AND operation |
| **Input value sockets** | `bool a` | First argument |
| `bool b` | Second argument |  |
| **Output value sockets** | `bool value` | True if and only if both $`a`$ and $`b`$ are true; false otherwise |

##### Boolean OR

|  |  |  |
|----|----|----|
| **Operation** | `math/or` | Boolean OR operation |
| **Input value sockets** | `bool a` | First argument |
| `bool b` | Second argument |  |
| **Output value sockets** | `bool value` | False if and only if both $`a`$ and $`b`$ are false; true otherwise |

##### Boolean XOR

|  |  |  |
|----|----|----|
| **Operation** | `math/xor` | Boolean XOR operation |
| **Input value sockets** | `bool a` | First argument |
| `bool b` | Second argument |  |
| **Output value sockets** | `bool value` | True if and only if $`a`$ is not equal to $`b`$; false otherwise |

#### Color Model Conversion Operations

##### RGB to OkLCh

|  |  |  |
|----|----|----|
| **Operation** | `math/rgbToOkLCh` | RGB to OkLCh conversion operation |
| **Input value sockets** | `float r` | Red value |
| `float g` | Green value |  |
| `float b` | Blue value |  |
| **Output value sockets** | `float l` | Lightness value |
| `float c` | Chroma value |  |
| `float h` | Hue value in radians |  |

> [!CAUTION]
> Although this operation assumes that input values represent linear
> color values from the BT.709 gamut, it does not perform any input or
> output clamping or gamut mapping.

The output values are computed as follows:

1.  Let $`L'`$, $`M'`$, and $`S'`$ be

    <div class="informalequation">

    ``` math
    ((L'), (M'), (S')) = ((0.4122214708, 0.5363325363, 0.0514459929),
                          (0.2119034982, 0.6806995451, 0.1073969566),
                          (0.0883024619, 0.2817188376, 0.6299787005)) cdot ((r), (g), (b))
    ```

    </div>

2.  Then $`L`$, $`a`$, and $`b`$ values are

    <div class="informalequation">

    ``` math
    ((L), (a), (b)) = ((+0.2104542553, +0.7936177850, -0.0040720468),
                       (+1.9779984951, -2.4285922050, +0.4505937099),
                       (+0.0259040371, +0.7827717662, -0.8086757660)) cdot ((\root[3\]{L'}), (\root[3\]{M'}), (\root[3\]{S'}))
    ```

    </div>

    > [!CAUTION]
    > It is important to use a cube root implementation that supports
    > negative values, such as `Math.cbrt` in ECMAScript.

3.  Set the `l` output value to the value of $`L`$.

4.  Set the `c` output value to $`sqrt(a^2 + b^2)`$.

5.  Set the `h` output value to the result of the `math/atan2` operation
    with $`a`$ and $`b`$ input values swapped.

Since this operation is a shortcut for the combination of arithmetic,
exponential, and trigonometry operations, NaN and infinity values are
propagated accordingly.

> [!TIP]
> The constant matrix values above were taken from the original OkLab
> document and are optimized for single-precision computations. When
> implementing this operation on platforms that support only
> double-precision arithmetic, such as ECMAScript, consider using the
> revised matrix values that can be found in CSS Color Module Level 4.

> [!TIP]
> This operation does not implicitly clamp the input values. If needed,
> that step could be done explicitly by adding interactivity nodes with
> the `math/saturate` operation.

##### OkLCh to RGB

|  |  |  |
|----|----|----|
| **Operation** | `math/rgbFromOkLCh` | OkLCh to RGB conversion operation |
| **Input value sockets** | `float l` | Lightness value |
| `float c` | Chroma value |  |
| `float h` | Hue value in radians |  |
| **Output value sockets** | `float r` | Red value |
| `float g` | Green value |  |
| `float b` | Blue value |  |

> [!CAUTION]
> This operation produces negative of greater than one RGB values for
> input OkLCh values that are outside of the BT.709 gamut. This
> operation does not perform any input or output clamping or gamut
> mapping.

The output values are computed as follows:

1.  Let $`L`$, $`C`$, and $`h`$ be equal to the `l`, `c`, and `h` input
    values respectively.

2.  Let $`L'`$, $`M'`$, and $`S'`$ values be

    <div class="informalequation">

    ``` math
    ((L'), (M'), (S')) = ((1.0, +0.3963377774, +0.2158037573),
                          (1.0, -0.1055613458, -0.0638541728),
                          (1.0, -0.0894841775, -1.2914855480)) cdot ((L), (C \cdot \cos(h)), (C \cdot \sin(h)))
    ```

    </div>

3.  Then the `r`, `g`, and `b` output values are computed as

    <div class="informalequation">

    ``` math
    ((r), (g), (b)) = ((+4.0767416621, -3.3077115913, +0.2309699292),
                       (-1.2684380046, +2.6097574011, -0.3413193965),
                       (-0.0041960863, -0.7034186147, +1.7076147010)) cdot ((L'^3), (M'^3), (S'^3))
    ```

    </div>

Since this operation is a shortcut for the combination of arithmetic,
exponential, and trigonometry operations, NaN and infinity values are
propagated accordingly.

> [!TIP]
> The constant matrix values above were taken from the original OkLab
> document and are optimized for single-precision computations. When
> implementing this operation on platforms that support only
> double-precision arithmetic, such as ECMAScript, consider using
> revised matrix values that can be found in CSS Color Module Level 4.

> [!TIP]
> This operation does not implicitly clamp the output values. If needed,
> that step could be done explicitly by adding interactivity nodes with
> the `math/saturate` operation.

### Reference Operations

#### Reference Comparison Operations

##### Equality

|  |  |  |
|----|----|----|
| **Operation** | `ref/eq` | Equality operation |
| **Input value sockets** | `ref a` | First reference |
| `ref b` | Second reference |  |
| **Output value sockets** | `bool value` | True if the input arguments are equal; false otherwise |

The `value` output value is determined as follows:

1.  If both input values are null references,

    1.  set the `value` output value to true and skip the next steps.

2.  If one of the input values is a null reference and another input
    value is not a null reference,

    1.  set the `value` output value to false and skip the next steps.

3.  If both input values refer to the same object regardless of whether
    that object exists,

    1.  set the `value` output value to true and skip the next step.

4.  Set the `value` output value to false.

### Type Conversion Operations

#### Boolean Conversion Operations

##### Boolean to Integer

|  |  |  |
|----|----|----|
| **Operation** | `type/boolToInt` | Boolean to integer conversion |
| **Input value sockets** | `bool a` | Argument |
| **Output value sockets** | `int value` | $`1`$ if $`a`$ is true; $`0`$ otherwise |

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> a | 0
> ```

##### Boolean to Float

|  |  |  |
|----|----|----|
| **Operation** | `type/boolToFloat` | Boolean to float conversion |
| **Input value sockets** | `bool a` | Argument |
| **Output value sockets** | `float value` | $`1`$ if $`a`$ is true; $`0`$ otherwise |

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> +a
> ```

#### Integer Conversion Operations

##### Integer to Boolean

|  |  |  |
|----|----|----|
| **Operation** | `type/intToBool` | Integer to boolean conversion |
| **Input value sockets** | `int a` | Argument |
| **Output value sockets** | `bool value` | True if $`a`$ is not equal to zero; false otherwise |

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> !!a
> ```

##### Integer to Float

|  |  |  |
|----|----|----|
| **Operation** | `type/intToFloat` | Integer to float conversion |
| **Input value sockets** | `int a` | Argument |
| **Output value sockets** | `float value` | Floating-point value equal to $`a`$ |

Since floating-point values have double precision, this conversion
**MUST** be lossless.

This operation **MUST NOT** produce negative zero.

> [!TIP]
> This operation is no-op in ECMAScript.

#### Float Conversion Operations

##### Float to Boolean

|  |  |  |
|----|----|----|
| **Operation** | `type/floatToBool` | Float to boolean conversion |
| **Input value sockets** | `float a` | Argument |
| **Output value sockets** | `bool value` | False if $`a`$ is NaN or equal to zero; true otherwise |

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> !!a
> ```

##### Float to Integer

|  |  |  |
|----|----|----|
| **Operation** | `type/floatToInt` | Float to integer conversion |
| **Input value sockets** | `float a` | Argument |
| **Output value sockets** | `int value` | Integer value produced as described below |

1.  If the $`a`$ input value is zero, infinite, or NaN, return zero and
    skip the next steps.

2.  Let $`t`$ be $`a`$ with its fractional part removed by truncating
    towards zero.

3.  Let $`k`$ be a value of the same sign as $`t`$ such that its
    absolute value is less than $`2^32`$ and $`k`$ is equal to
    $`t - q * 2^32`$ for some integer $`q`$.

4.  If $`k`$ is greater than or equal to $`2^31`$, return $`k - 2^32`$;
    otherwise return $`k`$.

> [!TIP]
> This is implementable in ECMAScript via the following expression:
>
> ``` js
> a | 0
> ```

### Control Flow Operations

#### Sync Operations

##### Sequence

|  |  |  |
|----|----|----|
| **Operation** | `flow/sequence` | Sequentially activate all connected output flows |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Output flow sockets** | `<id>` | Zero or more output flows; their ids define the order of activation |

This operation has no internal state.

When the `in` input flow is activated, all output flows are activated
sequentially (each output flow is activated after the previous output
flow completes) in the order as described in the [Socket
Order](#socket-order) section.

If the number of output flow sockets (as present in JSON) exceeds an
implementation-defined limit, the graph **MUST** be rejected.

##### Branch

|  |  |  |
|----|----|----|
| **Operation** | `flow/branch` | Branch the execution flow based on a condition |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `bool condition` | Value selecting the branch taken |
| **Output flow sockets** | `true` | The flow to be activated if the `condition` input value is true |
| `false` | The flow to be activated if the `condition` input value is false |  |

This operation has no internal state.

The `condition` input value is evaluated on every execution.

##### Switch

|  |  |  |
|----|----|----|
| **Operation** | `flow/switch` | Conditionally route the execution flow to one of the outputs |
| **Configuration** | `int[] cases` | The cases on which to perform the switch; empty in the default configuration |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `int selection` | The value on which the switch operates |
| **Output flow sockets** | `<case>` | Zero or more output flows; `<case>` is an integer decimal number |
| `default` | The output flow activated when the `selection` input value is not present in the `cases` configuration array |  |

> [!CAUTION]
> The configuration of this operation affects its flow sockets.

The operation has zero or more `<case>` output flow sockets
corresponding to the elements of the `cases` configuration array.

In the default configuration, the `cases` configuration array is empty
and the operation has only the `default` output flow socket.

The following procedure defines output flow sockets generation from the
provided configuration:

1.  If the `cases` configuration property is not present or if it is not
    an array, ignore it and use the default configuration.

2.  If the `cases` configuration property is present and it is an array,
    then for each array element `C`:

    1.  if `C` is not a literal number or if it is not exactly
        representable as a 32-bit signed integer, ignore the `cases`
        property and use the default configuration;

        > [!TIP]
        > The integer representation check is implementable in
        > ECMAScript via the following expression:
        >
        > ``` js
        > C === (C | 0)
        > ```

    2.  convert `C` to a base-10 string representation `S` containing
        only decimal integers (ASCII characters `0x30 …​ 0x39`) and a
        leading minus sign (ASCII character `0x2D`) if `C` is negative;
        extra leading zeros **MUST NOT** be present;

    3.  add a flow socket `S` to the set of the output flow sockets of
        this operation or ignore it if an output flow socket with the
        same id has been already added.

3.  If the number of generated flow sockets plus one exceeds an
    implementation-defined limit on the maximum number of output flow
    sockets, the graph **MUST** be rejected.

4.  Proceed with the generated output flow sockets.

<div class="note">

<div class="title">

Examples

</div>

- If the `cases` configuration array is `[0.5, 1]`, the default
  configuration is used because `0.5` is not representable as a 32-bit
  signed integer.

- If the `cases` configuration array is `[-2147483649, 0]`, the default
  configuration is used because `-2147483649` is not representable as a
  32-bit signed integer.

- If the `cases` configuration array is `[-1.0, 0, 1]`, the output
  socket ids are exactly `"-1"`, `"0"`, and `"1"` because `-1.0` is
  equal to an integer `-1`.

- If the `cases` configuration array is `[0.1e1, 2, 2]`, the output
  socket ids are exactly `"1"` and `"2"` because `0.1e1` is equal to an
  integer `1` and the duplicate entry is ignored.

</div>

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate the `selection` input value.

2.  If the `cases` configuration array does not contain the `selection`
    input value:

    1.  activate the `default` output flow if it is connected.

3.  If the `cases` configuration array contains the `selection` input
    value:

    1.  activate the output flow with the matching id if it is
        connected.

##### While Loop

|  |  |  |
|----|----|----|
| **Operation** | `flow/while` | Repeatedly activate the output flow based on a condition |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `bool condition` | Loop condition |
| **Output flow sockets** | `loopBody` | The flow to be activated while the `condition` input value is true |
| `completed` | The flow to be activated once the `condition` input value is false |  |

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate the `condition` input value.

2.  If the `condition` is true,

    1.  activate the `loopBody` output flow;

    2.  after completion of the `loopBody` output flow, self-activate
        the `in` input flow.

3.  If the `condition` is false,

    1.  activate the `completed` output flow.

##### For Loop

|  |  |  |
|----|----|----|
| **Operation** | `flow/for` | Repeatedly activate the output flow based on an incrementing index value |
| **Configuration** | `int initialIndex` | The index value before the loop starts; zero in the default configuration |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `int startIndex` | The start index of the loop |
| `int endIndex` | The end index of the loop |  |
| **Output flow sockets** | `loopBody` | The flow to be activated if the `index` value is less than the `endIndex` input value |
| `completed` | The flow to be activated if the `index` value is greater than or equal to the `endIndex` input value |  |
| **Output value sockets** | `int index` | The current index value if the interactivity node has ever been activated, `initialIndex` otherwise |

In the default configuration, the `initialIndex` configuration value is
zero.

If the `initialIndex` configuration property is not provided by the
behavior graph, if it is not a literal number, or if its value is not
exactly representable as a 32-bit signed integer, the default
configuration **MUST** be used.

The internal state of this operation consists of one 32-bit signed
integer value `index` initialized to `initialIndex`.

When the `in` input flow is activated:

1.  Evaluate the `startIndex` input value.

2.  Set `index` to `startIndex`.

3.  Evaluate the `endIndex` input value.

4.  If `index` is less than the `endIndex` input value,

    1.  activate the `loopBody` output flow;

    2.  after completion of the `loopBody` output flow, increment the
        `index` value by 1;

    3.  self-activate the `in` input flow and goto step 3, i.e., skip
        steps 1 and 2;

5.  If the `index` value is greater than or equal to the `endIndex`
    input value,

    1.  activate the `completed` output flow.

##### Do N

|  |  |  |
|----|----|----|
| **Operation** | `flow/doN` | Activate the output flow no more than N times |
| **Input flow sockets** | `in` | The entry flow into this operation |
| `reset` | When this flow is activated, the `currentCount` value is reset to 0 |  |
| **Input value sockets** | `int n` | Maximum number of times the `out` output flow is activated |
| **Output flow sockets** | `out` | The flow to be activated if the `currentCount` value is less than the `n` input value |
| **Output value sockets** | `int currentCount` | The current execution count |

The internal state of this operation consists of one 32-bit signed
integer value `currentCount` initialized to 0.

When the `reset` input flow is activated:

1.  Reset `currentCount` to 0.

When the `in` input flow is activated:

1.  Evaluate the `n` input value.

2.  If `currentCount` is less than `n`,

    1.  increment `currentCount` by 1;

    2.  activate the `out` output flow.

##### Multi Gate

|  |  |  |
|----|----|----|
| **Operation** | `flow/multiGate` | Route the execution flow to one of the outputs sequentially or randomly |
| **Configuration** | `bool isRandom` | If set to true, output flows are activated in random order, picking a random not used output flow each time until all are done; false in the default configuration |
| `bool isLoop` | If set to true, output flow activations will repeat in a loop continuously after all are done; false in the default configuration |  |
| **Input flow sockets** | `in` | The entry flow into this operation |
| `reset` | When this flow is activated, the `lastIndex` value is reset to -1 and all outputs are marked as not used |  |
| **Output flow sockets** | `<id>` | Zero or more output flows; their ids define the order of activation |
| **Output value sockets** | `int lastIndex` | The index of the last used output; `-1` if the interactivity node has not been activated |

If the number of output flow sockets (as present in JSON) exceeds an
implementation-defined limit, the graph **MUST** be rejected.

In the default configuration, both `isRandom` and `isLoop` configuration
values are false.

If any of the two configuration properties is not provided by the
behavior graph or if it is not a literal boolean, the default
configuration for both properties **MUST** be used.

The internal state of this operation consists of one 32-bit signed
integer value `lastIndex` initialized to -1 and an array of booleans
with all values initialized to false representing used output flows. The
size of the boolean array is equal to the number of output flows.

For the purposes of the `in` input flow operation, the output flows are
assigned internal indices starting with zero in the order as described
in the [Socket Order](#socket-order) section.

When the `reset` input flow is activated:

1.  Reset the `lastIndex` value to -1.

2.  Mark all output flows as not used in the boolean array.

When the `in` input flow is activated:

1.  If the `isRandom` configuration value is false,

    1.  let `i` be the smallest not used output flow index according to
        the boolean array or -1 if all output flows are marked as used.

2.  If the `isRandom` configuration value is true,

    1.  let `i` be a random not used output flow index according to the
        boolean array or -1 if all output flows are marked as used.

3.  If `i` is greater than -1,

    1.  mark the output flow with index `i` as used in the boolean
        array;

    2.  set the `lastIndex` value to `i`;

    3.  activate the output flow with index `i`.

4.  If `i` is equal to -1 and the `isLoop` configuration value is true,

    1.  mark all output flows as not used in the boolean array;

    2.  if the `isRandom` configuration value is false,

        1.  set `i` to 0;

    3.  if the `isRandom` configuration value is true,

        1.  set `i` to a random output flow index;

    4.  mark the output flow with index `i` as used in the boolean
        array;

    5.  set the `lastIndex` value to `i`;

    6.  activate the output flow with index `i`.

When the `isRandom` and `isLoop` configuration values are true, the
output flow activation order **SHOULD** be randomized on each loop
iteration.

##### Wait All

|  |  |  |
|----|----|----|
| **Operation** | `flow/waitAll` | Activate the output flow when all input flows have been activated at least once. |
| **Configuration** | `int inputFlows` | The number of input flows; zero in the default configuration |
| **Input flow sockets** | `<i>` | The `i`-th input flow, `i` is a non-negative integer decimal number less than the `inputFlows` configuration value |
| `reset` | When this flow is activated, all input flows are marked as unused |  |
| **Output flow sockets** | `out` | The flow to be activated after every input flow activation except the last missing input |
| `completed` | The flow to be activated when the last missing input flow is activated |  |
| **Output value sockets** | `int remainingInputs` | The number of not yet activated input flows |

> [!CAUTION]
> The configuration of this operation affects its flow sockets.

The operation has from zero to 64 input flow sockets with ids assigned
sequential non-negative integer decimal numbers depending on the
`inputFlows` configuration value. Encoded as base-10 strings, these
input flow socket ids contain only decimal integers (ASCII characters
`0x30 …​ 0x39`); other characters and leading zeros are not used.

For example, if `inputFlows` is 3, the input flow socket ids are `"0"`,
`"1"`, and `"2"` exactly.

In the default configuration, the `inputFlows` configuration value is
zero.

If the `inputFlows` configuration property is not provided by the
behavior graph, if it is not a literal number, if its value is not
exactly representable as an integer, if it is negative, or if it is
greater than 64, the default configuration **MUST** be used.

The internal state of this operation consists of one 32-bit signed
integer value `remainingInputs` initialized to the value of the
`inputFlows` configuration property and an array of booleans with all
values initialized to false representing activated input flow sockets.
The size of the boolean array is equal to the value of the `inputFlows`
configuration property.

When the `reset` input flow is activated:

1.  Reset `remainingInputs` to the value of the `inputFlows`
    configuration property.

2.  Mark all input flows as not activated in the boolean array.

When any of the `<i>` input flows is activated:

1.  If the `<i>`-th input flow is not marked as activated in the boolean
    array:

    1.  mark the `<i>`-th input flow as activated in the boolean array;

    2.  decrement the `remainingInputs` value by 1.

2.  If the `remainingInputs` value is zero:

    1.  activate the `completed` output flow.

3.  If the `remainingInputs` value is not zero:

    1.  activate the `out` output flow.

> [!NOTE]
> In the default configuration, this operation has only the `reset`
> input flow, the `remainingInputs` output value is always zero, and the
> output flows are never activated.

##### Throttle

|  |  |  |
|----|----|----|
| **Operation** | `flow/throttle` | Activate the output flow unless it has been activated less than a certain time ago |
| **Input flow sockets** | `in` | The entry flow into this operation |
| `reset` | When this flow is activated, the output flow throttling state is reset |  |
| **Input value sockets** | `float duration` | The time, in seconds, to wait after an output flow activation before allowing subsequent output flow activations |
| **Output flow sockets** | `out` | The flow to be activated if the output flow is not currently throttled |
| `err` | The flow to be activated if the `duration` input value is negative, infinite, or NaN |  |
| **Output value sockets** | `float lastRemainingTime` | The remaining throttling time, in seconds, at the moment of the last valid activation of the input flow or NaN if the input flow has never been activated with a valid `duration` input value |

The internal state of this operation consists of an uninitialized
*timestamp* value of an implementation-defined high-precision time type
and a floating-point `lastRemainingTime` value initialized to NaN.

When the `reset` input flow is activated:

1.  Reset the `lastRemainingTime` value to NaN.

When the `in` input flow is activated:

1.  Evaluate the `duration` input value.

2.  If the `duration` input value is NaN, infinite, negative, or not
    convertible into an implementation-specific time type used for the
    internal *timestamp* value,

    1.  activate the `err` output flow and skip the next steps.

3.  If the `lastRemainingTime` value is not NaN:

    1.  Let `elapsed` be a non-negative difference, in seconds, between
        the *timestamp* and the current time.

    2.  If the `duration` input value is less than or equal to the
        `elapsed` value,

        1.  set the *timestamp* value to the current time;

        2.  set the `lastRemainingTime` value to zero;

        3.  activate the `out` output flow.

    3.  If the `duration` input value is greater than the `elapsed`
        value,

        1.  set the `lastRemainingTime` value to the positive
            difference, in seconds, between the `duration` and `elapsed`
            values.

4.  If the `lastRemainingTime` value is NaN,

    1.  set the *timestamp* value to the current time;

    2.  set the `lastRemainingTime` value to zero;

    3.  activate the `out` output flow.

#### Delay Operations

##### Set Delay

|  |  |  |
|----|----|----|
| **Operation** | `flow/setDelay` | Schedule the output flow activation after a certain delay |
| **Input flow sockets** | `in` | The entry flow into this operation |
| `cancel` | When this flow is activated, all delayed activations scheduled by this interactivity node are cancelled |  |
| **Input value sockets** | `float duration` | The duration, in seconds, to delay the `done` output flow activation |
| **Output value sockets** | `ref lastDelay` | The reference to a delay scheduled during the last successful execution of the interactivity node |
| **Output flow sockets** | `out` | The flow to be activated if the `duration` value is valid |
| `err` | The flow to be activated if the `duration` value is invalid |  |
| `done` | The flow to be activated after the delay |  |

The internal state of this operation consists of a reference `lastDelay`
value initialized to null and a dynamic array of activation references
scheduled by the interactivity node executions. This array is initially
empty and its maximum size is implementation-specific.

The internal state of an execution graph having one or more
interactivity nodes with the `flow/setDelay` operation includes a
dynamic array of activation references scheduled from all such
interactivity nodes. This array is initially empty and its maximum size
is implementation-specific.

Implementations **MUST** be aware of their effective limit on the
maximum supported `duration` input value to avoid any implicit behavior
changes, e.g., due to numeric overflows; exceeding such value **MUST**
lead to the `err` output flow activation as described below.

When the `in` input flow is activated:

1.  Evaluate the `duration` input value.

2.  If the `duration` input value is NaN, infinite, negative, or not
    convertible into an implementation-specific time type,

    1.  activate the `err` output flow and skip the next steps.

3.  If scheduling a new activation exceeds an implementation-specific
    limit on the maximum number of simultaneous delays,

    1.  activate the `err` output flow and skip the next steps.

4.  Let *activationTime* be an implementation-defined high-precision
    time value equal to the sum of the current time value and the
    `duration` input value converted to the same time type.

5.  If *activationTime* is not valid according to
    implementation-specific validation rules, e.g., it exceeds an
    internal threshold value,

    1.  activate the `err` output flow and skip the next steps.

6.  Set `lastDelay` to a non-null reference value representing the
    delayed flow activation being scheduled. This value **MUST** be
    unique across all delay reference values of all interactivity nodes
    with the `flow/setDelay` operation.

7.  Push the value of `lastDelay` to the graph and interactivity node
    arrays of activation references.

8.  Schedule the following actions at the *activationTime* time:

    1.  Removal of the activation reference value from both arrays of
        activation references.

    2.  Activation of the `done` output flow.

9.  Activate the `out` output flow.

When the `cancel` input flow is activated:

1.  Set the `lastDelay` value to null.

2.  For each activation reference value in the interactivity node’s
    array of activation references:

    1.  Remove this activation reference value from the interactivity
        node’s and the graph’s arrays of activation references.

    2.  Cancel the corresponding scheduled activation.

##### Cancel Delay

|  |  |  |
|----|----|----|
| **Operation** | `flow/cancelDelay` | Cancel a previously scheduled output flow activation |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `ref delay` | The reference value of the scheduled activation to be cancelled |
| **Output flow sockets** | `out` | The flow to be activated after executing this operation |

This operation has no internal state but its execution **MAY** affect
internal states of other operations and the graph.

When the `in` input flow is activated:

1.  Evaluate the `delay` input value.

2.  Remove this activation reference value from all arrays of activation
    references if it exists.

3.  Cancel the corresponding scheduled activation if it exists.

4.  Activate the `out` output flow.

Null or invalid delay reference values **MUST NOT** cause any runtime
errors.

### State Manipulation Operations

#### Custom Variable Access

##### Variable Get

|                          |                |                             |
|--------------------------|----------------|-----------------------------|
| **Operation**            | `variable/get` | Get a custom variable value |
| **Configuration**        | `int variable` | The custom variable index   |
| **Output value sockets** | `T value`      | The custom variable value   |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value socket.

This operation gets a custom variable value using the variable index
provided by the `variable` configuration value.

The type `T` is determined by the referenced variable. The variable
index **MUST** be a non-negative integer less than the total number of
custom variables, otherwise the interactivity node is invalid and the
graph **MUST** be rejected.

This operation has no internal state.

##### Variable Set

|  |  |  |
|----|----|----|
| **Operation** | `variable/set` | Set one or more custom variable values |
| **Configuration** | `int[] variables` | The array containing variable indices |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `Ti <index>` | One or more input value sockets; `<index>` refers to the corresponding variable index and `Ti` refers to its type |
| **Output flow sockets** | `out` | The flow to be activated after the values are set |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value sockets.

This operation sets multiple custom variable values using the variable
indices provided by the `variables` configuration value and the
corresponding input values.

The following procedure defines input value sockets generation from the
provided configuration:

1.  If the `variables` configuration property is not present or if it is
    not a non-empty array, the interactivity node is invalid and the
    graph **MUST** be rejected.

2.  If the `variables` configuration property is present and it is a
    non-empty array, then for each array element `V`:

    1.  if `V` is not a valid custom variable index, i.e., it is not a
        non-negative integer less than the total number of custom
        variables, the interactivity node is invalid and the graph
        **MUST** be rejected;

    2.  convert `V` to a base-10 string representation `S` containing
        only decimal integers (ASCII characters `0x30 …​ 0x39`); extra
        leading zeros **MUST NOT** be present;

    3.  add a value socket with id `S` and the type corresponding to the
        type of the custom variable with index `V` to the set of the
        input value sockets of this operation or ignore it if an input
        value socket with the same id has been already added.

3.  If the number of generated value sockets exceeds an
    implementation-defined limit on the maximum number of input value
    sockets, the graph **MUST** be rejected.

4.  Proceed with the generated input value sockets.

If the interactivity node’s JSON object does not contain all input value
sockets generated by the procedure above with proper types, the
interactivity node is invalid and the graph **MUST** be rejected.

Extra input value sockets with ids not present in the output of the
procedure above do not affect the interactivity node’s operation and
validation but they still **MUST** have valid types and value sources.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  For each unique element `V` of the `variables` configuration array:

    1.  if the *variable interpolation state dynamic array* (defined
        below) contains an entry with the variable index `V`, remove the
        entry from that array;

    2.  set the custom variable with the index `V` to the value of the
        `V` input value socket.

3.  Activate the `out` output flow.

##### Variable Interpolate

|  |  |  |
|----|----|----|
| **Operation** | `variable/interpolate` | Interpolate a variable value |
| **Configuration** | `int variable` | The custom variable index |
| `bool useSlerp` | Whether to use spherical interpolation for quaternions |  |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `T value` | The target variable value |
| `float duration` | The time, in seconds, in which the variable **SHOULD** reach the target value |  |
| `float2 p1` | Control point P1 |  |
| `float2 p2` | Control point P2 |  |
| **Output flow sockets** | `out` | The flow to be activated if the input values are valid |
| `err` | The flow to be activated if the input values are invalid |  |
| `done` | The flow to be activated when the variable reaches the target value |  |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value socket.

This operation interpolates and updates the specified custom variable
multiple times over the specified duration.

The type `T` is determined by the referenced variable. The variable
index **MUST** be a non-negative integer less than the total number of
custom variables, otherwise the interactivity node is invalid and the
graph **MUST** be rejected.

If the referenced variable is integer or boolean, the interactivity node
is invalid and the graph **MUST** be rejected.

The `useSlerp` configuration value **MUST** be a boolean literal and it
**MUST NOT** be true if the type `T` is not `float4`, otherwise the
interactivity node is invalid and the graph **MUST** be rejected.

This operation has no internal state.

The internal state of an execution graph having one or more
interactivity nodes with the `variable/interpolate` operation includes
an implementation-defined *variable interpolation state dynamic array*
each element of which contains the following data:

- The reference to the variable being interpolated

- Implementation-defined high precision timestamp value representing the
  interpolation start time

- Interpolation duration value converted to the implementation-defined
  high precision time type

- Variable value at the time of the successful interactivity node
  activation

- Information needed for cubic Bézier spline evaluation derived from the
  interactivity node’s input values

- Target variable value

- Implementation-specific pointer to the `done` output flow of the
  interactivity node that has added this entry

This array is initially empty and its maximum size is
implementation-specific.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If the `duration` input value is NaN, infinite, negative, or not
    convertible into an implementation-specific time type used for the
    internal interpolation start time value,

    1.  activate the `err` output flow and skip the next steps.

3.  If any component of the `p1` or `p2` input values is NaN or infinite
    or if any of the first components of these input values is negative
    or greater than 1,

    1.  activate the `err` output flow and skip the next steps.

4.  If starting a new variable interpolation exceeds an
    implementation-specific limit on the maximum number of simultaneous
    variable interpolations,

    1.  activate the `err` output flow and skip the next steps.

5.  If the *variable interpolation state dynamic array* contains an
    entry with the same variable reference,

    1.  remove it from the array.

6.  Using the implicitly-defined end points $`P_0 (0, 0)`$ and
    $`P_3 (1, 1)`$ together with the control points $`P_1`$ and $`P_2`$
    provided via the input values construct a cubic Bézier easing
    function for the $`[0, 1`$\] input range.

7.  Add a new entry to the *variable interpolation state dynamic array*
    filling it with the required information based on the evaluated
    input values.

8.  Activate the `out` output flow.

On each tick, for each entry of the *variable interpolation state
dynamic array*:

1.  Compute the current input progress position *t* as the time passed
    since the interpolation start divided by the interpolation’s
    duration.

2.  If *t* is less than or equal to zero,

    1.  skip the next steps.

3.  If *t* is NaN or greater than or equal to 1,

    1.  set the variable to the target value;

    2.  remove the current entry from the *variable interpolation state
        dynamic array*;

    3.  activate the `done` output flow linked to the current entry;

    4.  skip the next steps.

4.  Using the cubic Bézier spline information, compute the output
    progress position *q* based on the *t* value. This step implies that
    $`t \in (0; 1)`$.

5.  Set the variable to the new value computed as a linear or spherical
    linear interpolation depending on the `useSlerp` configuration value
    between the original and the target variable values using the output
    progress position *q* as the interpolation coefficient.

> [!NOTE]
> Certain control point values can cause the intermediate output
> progress value to be negative or greater than one. This is not an
> error.

#### Object Model Access

Operations defined in this section use JSON Pointers ([RFC
6901](#rfc6901)) to refer to glTF Asset Object Model properties. These
pointers are generated from JSON Pointer Templates specified in the
`pointer` configuration values.

JSON Pointers always refer to the properties of the glTF asset that
contains the behavior graph. Existence and validity of properties
accessed via JSON Pointers do not depend on the current glTF scene
index.

> [!NOTE]
> For example:
>
> - The `/nodes/0/translation` pointer denotes the translation of the
>   glTF node with index 0 in glTF coordinate system.
>
> - The `/nodes/1/rotation` pointer denotes the rotation quaternion of
>   the glTF node with index 1 in glTF coordinate system using the glTF
>   order of quaternion components, i.e., XYZW, where W is the scalar.
>
> Both pointers are functional even if the glTF nodes do not belong to
> the current glTF scene.
>
> Implementations that import glTF assets into pre-existing scenes may
> need to maintain mappings between their internal objects and glTF
> objects defined in the asset. If the implementation’s coordinate
> system is different from the one used in glTF, extra runtime
> conversions may be necessary for properties that depend on the XYZ
> axes.

When a behavior graph is loaded, all JSON Pointer Templates **MUST** be
processed as described in the following sections. If a pointer template
contains path segments wrapped in square or curly brackets, called
*template parameters*, they define input value socket ids (with the
square or curly brackets stripped) for the interactivity node. These
template parameters **MUST NOT** be empty; the same parameter **MUST
NOT** be used more than once within a template string. If used
literally, square and curly brackets **MUST** be doubled, i.e, `{`
**MUST** be written as `{{`, and `}` **MUST** be written as `}}` when
used within path segments; square or curly brackets **MUST NOT** be used
within parameters. Tilde (`~`) and forward slash (`/`) characters used
in path segments or parameters **MUST** be encoded as `~0` and `~1`
respectively as defined in [RFC 6901](#rfc6901).

> [!NOTE]
> None of the glTF properties currently defined in Khronos
> specifications contain square or curly brackets, forward slash, or
> tilde in their names but such properties can exist in arbitrary glTF
> assets within vendor-specific extensions or `extras` objects.

When an Object Model Access operation is activated, its JSON Pointer
Template and input values (if present) are used to generate the
effective JSON Pointer string value.

If the property being accessed is also affected by a currently active
animation, the animation state **MUST** be applied before getting and/or
setting the property value via pointers.

##### JSON Pointer Template Parsing

The input to these steps is the `pointer` string configuration value;
the output includes a boolean validity flag and a template parameter
array. Each template parameter array entry consists of a string
representing the corresponding input value socket id, its type: integer
or reference, and the parameter substring location (e.g., start and end
offsets) in the JSON Pointer Template.

Implementations **MAY** optimize these steps as long as such
optimizations do not change the output.

1.  Let the validity flag be true and the template parameter array be
    empty.

2.  If the pointer template string is not a syntactically valid JSON
    Pointer as defined in [RFC 6901](#rfc6901) regardless of the pointer
    applicability to the glTF asset and/or template parameters, reject
    the pointer template string with a syntax error.

3.  Split the pointer template string at all matches of the forward
    slash character (`/`, `0x2F`). This step produces a path segment
    array consisting of a substring before the first match, substrings
    between the matches, and a substring after the last match.

4.  For each path segment substring produced during step 3:

    1.  If the path segment consists of a single left square bracket
        (`[`, `0x5B`) character or a single left curly bracket (`{`,
        `0x7B`) character,

        1.  set the validity flag to false, ignore all other segments,
            and goto step 5.

    2.  If the first character of the path segment substring is a left
        square bracket and the second character is not a left square
        bracket:

        1.  Assume the path segment substring to be an integer template
            parameter.

        2.  If the path segment substring contains left square or curly
            brackets not including the first character, right square
            (`]`, `0x5D`) or right curly (`}`, `0x7D`) brackets not
            including the last character, if it does not end with a
            right square bracket, or if there are no characters between
            the first and the last square brackets (i.e., if the entire
            path segment substring is `[]`), set the validity flag to
            false, ignore all other segments, and goto step 5.

        3.  Derive the input value socket id as follows:

            1.  Strip the first and the last characters, i.e., the
                leading left and trailing right square brackets.

            2.  Replace all instances of `~1` with `/`.

            3.  Replace all instances of `~0` with `~`.

        4.  If the template parameter array contains an element with the
            same value socket id regardless of the type, set the
            validity flag to false and goto step 5.

        5.  Add a new entry to the template parameter array consisting
            of the derived input value socket id, the integer type, and
            the path segment substring location in the pointer template
            string.

    3.  If the first character of the path segment substring is a left
        curly bracket and the second character is not a left curly
        bracket:

        1.  Assume the path segment substring to be a reference template
            parameter.

        2.  If the path segment substring contains left square or curly
            brackets not including the first character, right square or
            curly brackets not including the last character, if it does
            not end with a right curly bracket, or if there are no
            characters between the first and the last curly brackets
            (i.e., if the entire path segment substring is `{}`), set
            the validity flag to false, ignore all other segments, and
            goto step 5.

        3.  Derive the input value socket id as follows:

            1.  Strip the first and the last characters, i.e., the
                leading left and trailing right curly brackets.

            2.  Replace all instances of `~1` with `/`.

            3.  Replace all instances of `~0` with `~`.

        4.  If the template parameter array contains an element with the
            same value socket id, set the validity flag to false and
            goto step 5.

        5.  Add a new entry to the template parameter array consisting
            of the derived input value socket id, the reference type,
            and the path segment substring location in the pointer
            template string.

    4.  If the first character of the path segment substring is not a
        left square bracket or if the first two characters are left
        square brackets, or if the first character of the path segment
        substring is not a left curly bracket or if the first two
        characters are left curly brackets:

        1.  Assume the path segment substring to be a literal path
            segment, i.e., not a template parameter.

        2.  If the path segment substring contains an odd number of
            consecutive left square brackets, an odd number of
            consecutive right square brackets, an odd number of
            consecutive left curly brackets, or an odd number of
            consecutive right curly brackets, set the validity flag to
            false and goto step 5.

5.  If the validity flag is true, output the parameter array; if the
    validity flag is false, reject the pointer template string with a
    syntax error.

<div class="note">

<div class="title">

Valid Syntax Examples

</div>

- The template string `"/myProperty"` is syntactically valid and has no
  template parameters. As it does not represent a recognized glTF Asset
  Object Model property, using this pointer will result in runtime
  errors defined by the corresponding operations.

- The template string `"/nodes/0/scale"` is syntactically valid and has
  no template parameters thus it does not yield any input value socket
  ids.

- The template string `"/nodes/[index]/scale"` is syntactically valid
  and has one template parameter that yields an integer input value
  socket with id `index`.

- The template string `"/nodes/{index}/scale"` is syntactically valid
  and has one template parameter that yields a reference input value
  socket with id `index`.

- The template string `"/nodes/[index]/extras/{{index}}"` is
  syntactically valid and has one template parameter that yields an
  integer input value socket with id `index`. The curly brackets that
  are part of the `{index}` property name are doubled.

- The template string `"/nodes/{index}/extras/"` is syntactically valid
  and has one template parameter that yields a reference input value
  socket with id `index`. The square brackets that are part of the
  `[index]` property name are doubled.

- The template string `"/nodes/{~0~0index~0~0}/rotation"` is
  syntactically valid and has one template parameter that yields a
  reference input value socket with id `~~index~~`. The tilde characters
  used in the template parameter are encoded as `~0`.

- The template string `"/nodes/[my~1index]/scale"` is syntactically
  valid and has one template parameter that yields an integer input
  value socket with id `my/index`. The forward slash character used in
  the template parameter is encoded as `~1`.

</div>

<div class="note">

<div class="title">

Invalid Syntax Examples

</div>

- The template string `"/nodes/{index}/extras/~2"` is syntactically
  invalid because the `~2` character sequence is invalid in JSON
  Pointers, see [RFC 6901](#rfc6901).

- The template string `"/nodes/[index]/weights/[index]"` is
  syntactically invalid because it yields two input value sockets with
  the same id.

- The template string `"/nodes/{index}/weights/[index]"` is
  syntactically invalid because it yields two input value sockets with
  the same id.

- The template string `"/nodes/[/scale"` is syntactically invalid
  because it contains a `[` path segment.

- The template string `"/nodes/{/scale"` is syntactically invalid
  because it contains a `{` path segment.

- The template string `"/nodes/[]/scale"` is syntactically invalid
  because the template parameter path segment has no characters between
  `[` and `]`.

- The template string `"/nodes/{}/scale"` is syntactically invalid
  because the template parameter path segment has no characters between
  `{` and `}`.

- The template string `"/nodes/[index/scale"` is syntactically invalid
  because the template parameter path segment does not end with `]`.

- The template string `"/nodes/{index/scale"` is syntactically invalid
  because the template parameter path segment does not end with `}`.

- The template string `"/nodes/[i[ndex]/scale"` is syntactically invalid
  because the template parameter path segment contains a left square
  bracket inside the parameter.

- The template string `"/nodes/[i{ndex]/scale"` is syntactically invalid
  because the template parameter path segment contains a left curly
  bracket inside the parameter.

- The template string `"/nodes/{i[ndex}/scale"` is syntactically invalid
  because the template parameter path segment contains a left square
  bracket inside the parameter.

- The template string `"/nodes/{i{ndex}/scale"` is syntactically invalid
  because the template parameter path segment contains a left curly
  bracket inside the parameter.

- The template string `"/nodes/[i]ndex]/scale"` is syntactically invalid
  because the template parameter path segment contains a right square
  bracket inside the parameter.

- The template string `"/nodes/[i}ndex]/scale"` is syntactically invalid
  because the template parameter path segment contains a right curly
  bracket inside the parameter.

- The template string `"/nodes/{i]ndex}/scale"` is syntactically invalid
  because the template parameter path segment contains a right square
  bracket inside the parameter.

- The template string `"/nodes/{i}ndex}/scale"` is syntactically invalid
  because the template parameter path segment contains a right curly
  bracket inside the parameter.

- The template string `"/nodes/0/extras/[[i[ndex]]"` is syntactically
  invalid because a literal path segment has an odd number of
  consecutive left square brackets.

- The template string `"/nodes/0/extras/{{i{ndex}}"` is syntactically
  invalid because a literal path segment has an odd number of
  consecutive left curly brackets.

- The template string `"/nodes/0/extras/[[index]"` is syntactically
  invalid because a literal path segment has an odd number of
  consecutive right square brackets.

- The template string `"/nodes/0/extras/{{index}"` is syntactically
  invalid because a literal path segment has an odd number of
  consecutive right curly brackets.

</div>

##### Effective JSON Pointer Generation

The inputs to these steps are the `pointer` configuration value, the
template parameter array, and the corresponding input values provided at
runtime by the behavior graph; the output is the effective JSON Pointer
string that will be handled by the Object Model Access operations.
Implementations **MAY** optimize these steps as long as such
optimizations do not change the output.

1.  Assume that the `pointer` configuration value is syntactically
    valid.

2.  Let *P* be a copy of the `pointer` configuration value.

3.  For each element of the template parameter array taken in the
    descending order of parameter substring locations:

    1.  If the parameter is an integer:

        1.  Assert that the corresponding input socket value is not
            negative.

        2.  Convert the corresponding input socket value to its decimal
            string representation containing only ASCII characters
            `0x30 …​ 0x39` with no extra leading zeros.

        3.  Update *P* by replacing the template parameter substring, as
            identified by the template parameter location, with the
            decimal string value of the corresponding input value.

    2.  If the parameter is a reference:

        1.  Assert that the corresponding input socket value is not a
            null reference.

        2.  Update *P* by replacing the template parameter substring, as
            identified by the template parameter location, with the
            implementation-specific representation of the corresponding
            input value.

4.  Update *P* by replacing all occurrences of the `[[` substring in it
    with `[`.

5.  Update *P* by replacing all occurrences of the `]]` substring in it
    with `]`.

6.  Update *P* by replacing all occurrences of the `{{` substring in it
    with `{`.

7.  Update *P* by replacing all occurrences of the `}}` substring in it
    with `}`.

8.  Output *P* as the effective JSON Pointer string.

<div class="note">

<div class="title">

Examples

</div>

- Let the `pointer` configuration value be `"/nodes/{N}/weights/[W]"`.
  Then the operations using this template pointer string have the `N`
  and `W` input value sockets with reference and integer types
  respectively. Let the runtime `N` value correspond to the node `<1>`
  and the runtime `W` value be 2. Then the effective JSON Pointer is
  `"/nodes/<1>/weights/2"` where `<1>` is the implementation-specific
  representation of the node 1.

- Let the `pointer` configuration value be
  `"/nodes/[index]/extras/{{index}}"`. Then the operations using this
  template pointer string have the integer `index` input value socket.
  Let the runtime `index` value be 2. Then the effective JSON Pointer is
  `"/nodes/2/extras/{index}"`.

</div>

##### Pointer Get

|  |  |  |
|----|----|----|
| **Operation** | `pointer/get` | Get an object model property value |
| **Configuration** | `string pointer` | JSON Pointer Template |
| `int type` | Property type index |  |
| **Input value sockets** | `int <parameter>` | Zero or more JSON Pointer integer template parameters to be evaluated at runtime; input value socket ids correspond to the pointer’s path segments wrapped with square brackets (`[]`) |
| `ref <parameter>` | Zero or more JSON Pointer reference template parameters to be evaluated at runtime; input value socket ids correspond to the pointer’s path segments wrapped with curly brackets (`{}`) |  |
| **Output value sockets** | `T value` | The resolved property value |
| `bool isValid` | True if the property value can be resolved; false otherwise |  |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value sockets.

This operation gets a glTF Asset Object Model property value using the
effective JSON Pointer string derived from the JSON Pointer Template
configuration value and the runtime values of the input value sockets.

The type `T` is determined by the `type` configuration value which
points to the element of the [`types`](#json-types) array. Input value
socket ids are defined by parsing the JSON Pointer Template string as
described above.

<div class="note">

<div class="title">

Examples

</div>

- If the `pointer` configuration value is `"/nodes/0/translation"`, the
  operation has no input value sockets and the pointer always refers to
  the `translation` property of the glTF node 0.

- If the `pointer` configuration value is `"/nodes/{myId}/scale"`, the
  operation has the `myId` reference input value socket, which value
  denotes the glTF node reference.

</div>

If the `pointer` configuration value is not provided, if it is not a
string, or if it is invalid (as defined in the previous sections), the
interactivity node is invalid and the graph **MUST** be rejected.

If the `type` configuration value is not provided, if it is not a
literal number, if it is not exactly representable as a 32-bit signed
integer, if it is negative, or if it is greater than or equal to the
length of the `types` array, the interactivity node is invalid and the
graph **MUST** be rejected.

If the number of input value sockets derived from the pointer template
string exceeds an implementation-specific limit on the maximum number of
input value sockets, the graph **MUST** be rejected.

When any of the output value sockets is accessed:

1.  Evaluate all input values.

2.  If any of the integer input values is negative or any of the
    reference input values is null:

    1.  set the `isValid` output value to false;

    2.  set the `value` output value to the default value for the type
        `T`;

    3.  skip the next steps.

3.  Generate the effective JSON Pointer as described in the previous
    sections.

4.  If the effective JSON Pointer cannot be resolved against the glTF
    asset or if the Object Model type of the resolved property does not
    match the type `T`,

    1.  set the `isValid` output value to false;

    2.  set the `value` output value to the default value for the type
        `T`;

    3.  skip the next steps.

5.  Set the `isValid` output value to true and the `value` output value
    to the value of the resolved glTF Asset Object Model property.

Pointers containing `extras` properties are out of scope of this
specification but **MAY** be supported by implementations.

<div class="note">

<div class="title">

Examples

</div>

- If the `pointer` configuration value is `"/nodes/[myId]/scale"`, the
  type `T` is `float3`, and the `myId` input value is negative or
  greater than or equal to the total number of glTF nodes, then the
  `isValid` output value is false and the `value` output value is
  `[NaN, NaN, NaN]`.

- If the `pointer` configuration value is `"/nodes/{myId}/scale"` and
  the type `T` is `float4`, then the `isValid` output value is false and
  the `value` output value is `[NaN, NaN, NaN, NaN]`. Note that `myId`
  input value becomes irrelevant in this case because even if it is
  valid the Object Model property type does not match the declared type
  `T`.

</div>

> [!NOTE]
> The `/nodes/{}/weights` pointer defined in the glTF Asset Object Model
> has the `float[]` type that is not supported by this extension. Any
> interactivity node with the `pointer/get` operation using that pointer
> would always have its `isValid` output value as false.

##### Pointer Set

|  |  |  |
|----|----|----|
| **Operation** | `pointer/set` | Set an object model property value |
| **Configuration** | `string pointer` | JSON Pointer Template |
| `int type` | Property type index |  |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `int <parameter>` | Zero or more JSON Pointer integer template parameters to be evaluated at runtime; input value socket ids correspond to the pointer’s path segments wrapped with square brackets (`[]`) |
| `ref <parameter>` | Zero or more JSON Pointer reference template parameters to be evaluated at runtime; input value socket ids correspond to the pointer’s path segments wrapped with curly brackets (`{}`) |  |
| `T value` | The new property value |  |
| **Output flow sockets** | `out` | The flow to be activated if the property was set |
| `err` | The flow to be activated if the property was not set |  |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value sockets.

This operation sets a glTF Asset Object Model property value using the
effective JSON Pointer string derived from the JSON Pointer Template
configuration value and the runtime values of the `<parameter>` input
value sockets.

The type `T` is determined by the `type` configuration value which
points to the element of the [`types`](#json-types) array. Input value
socket ids are defined by parsing the JSON Pointer Template string as
described above.

If the `pointer` configuration value is not provided, if it is not a
string, if it is invalid (as defined in the previous sections), or if it
contains a template parameter `[value]` or `{value}`, the interactivity
node is invalid and the graph **MUST** be rejected.

If the `type` configuration value is not provided, if it is not a
literal number, if it is not exactly representable as a 32-bit signed
integer, if it is negative, or if it is greater than or equal to the
length of the `types` array, the interactivity node is invalid and the
graph **MUST** be rejected.

If the number of input value sockets derived from the pointer template
string plus one exceeds an implementation-specific limit on the maximum
number of input value sockets, the graph **MUST** be rejected.

If the `value` input value is not valid for the resolved property, the
effective property value becomes implementation-defined and subsequent
`pointer/get` evaluations of the property **MAY** return any value of
the corresponding type until the property is updated with a valid value.
This is not an error. Implementations **MAY** generate runtime warnings
in this case as deemed possible.

> [!NOTE]
> If the resolved glTF property is `"/materials/0/emissiveFactor"` and
> it is being set to `[1, 2, 3]`, the effective emissive factor becomes
> undefined. Querying it afterwards with `pointer/get` could return any
> `float3` value including but not limited to `[0, 0, 0]`, `[1, 1, 1]`,
> `[1, 2, 3]`, or `[NaN, NaN, NaN]`.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If any of the `<parameter>` integer input values is negative or any
    of the `<parameter>` reference input values is null:

    1.  activate the `err` output flow and skip the next steps.

3.  Generate the effective JSON Pointer as described in the previous
    sections.

4.  If the effective JSON Pointer cannot be resolved against the glTF
    asset, if the Object Model type of the resolved property does not
    match the type `T`, or if the property is not mutable,

    1.  activate the `err` output flow and skip the next steps.

5.  If the *pointer interpolation state dynamic array* (defined in the
    next section) contains an entry with the effective JSON Pointer,

    1.  remove the entry from the array.

6.  Set the resolved glTF Asset Object Model property to the `value`
    input value.

7.  Activate the `out` output flow.

> [!NOTE]
> The `/nodes/{}/weights` pointer defined in the glTF Asset Object Model
> has the `float[]` type that is not supported by this extension. Any
> interactivity node with the `pointer/set` operation using that pointer
> would always activate only its `err` output flow.

##### Pointer Interpolate

|  |  |  |
|----|----|----|
| **Operation** | `pointer/interpolate` | Interpolate an object model property value |
| **Configuration** | `string pointer` | JSON Pointer Template |
| `int type` | Property type index |  |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `int <parameter>` | Zero or more JSON Pointer integer template parameters to be evaluated at runtime; input value socket ids correspond to the pointer’s path segments wrapped with square brackets (`[]`) |
| `ref <parameter>` | Zero or more JSON Pointer reference template parameters to be evaluated at runtime; input value socket ids correspond to the pointer’s path segments wrapped with curly brackets (`{}`) |  |
| `T value` | The target property value |  |
| `float duration` | The time, in seconds, in which the property **SHOULD** reach the target value |  |
| `float2 p1` | Control point P1 |  |
| `float2 p2` | Control point P2 |  |
| **Output flow sockets** | `out` | The flow to be activated if the property interpolation has been started |
| `err` | The flow to be activated if the property interpolation has not been started |  |
| `done` | The flow to be activated after the property reaches the target value |  |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value sockets.

This operation interpolates and updates the glTF Asset Object Model
property multiple times over the specified duration using the effective
JSON Pointer string derived from the JSON Pointer Template configuration
value, the runtime values of the `<parameter>` input value sockets, and
several interpolation inputs.

The type `T` is determined by the `type` configuration value which
points to the element of the [`types`](#json-types) array. Input value
socket ids are defined by parsing the JSON Pointer Template string as
described above.

If the `pointer` configuration value is not provided, if it is not a
string, if it is invalid (as defined in the previous sections), or if it
contains template parameters `[value]`, `{value}`, `[duration]`,
`{duration}`, `[p1]`, `{p1}`, `[p2]`, or `{p2}` the interactivity node
is invalid and the graph **MUST** be rejected.

If the `type` configuration value is not provided, if it is not a
literal number, if it is not exactly representable as a 32-bit signed
integer, if it is negative, if it is greater than or equal to the length
of the `types` array, or if it point to the type entry with `bool` or
`int` type signatures, the interactivity node is invalid and the graph
**MUST** be rejected.

If the number of input value sockets derived from the pointer template
string plus four exceeds an implementation-specific limit on the maximum
number of input value sockets, the graph **MUST** be rejected.

If the `value` input value or any intermediate interpolated value are
not valid for the resolved property, the effective property value
becomes implementation-defined and subsequent `pointer/get` evaluations
of the property **MAY** return any value of the corresponding type until
the property is updated with a valid value. This is not an error.
Implementations **MAY** generate runtime warnings in this case as deemed
possible.

> [!NOTE]
> If the resolved glTF property is
> `"/materials/0/pbrMetallicRoughness/metallicFactor"`, its current
> value is zero, and the interpolation target value is two, the
> effective metalness factor becomes undefined when the interpolated
> value is greater than one.

If the current glTF Asset Object Model property value is already
undefined due to previous invocations of `pointer/set` or
`pointer/interpolate` operations with invalid values (as defined above),
the interpolated property remains undefined during and after the
interpolation. This is not an error. Implementations **MAY** generate
runtime warnings in this case as deemed possible.

This operation has no internal state.

The internal state of an execution graph having one or more
interactivity nodes with the `pointer/interpolate` operation includes an
implementation-defined *pointer interpolation state dynamic array* each
element of which contains the following data:

- The resolved JSON Pointer to the Object Model property being
  interpolated

- Implementation-defined high precision timestamp value representing the
  interpolation start time

- Interpolation duration value converted to the implementation-defined
  high precision time type

- Object Model property value at the time of the successful
  interactivity node activation

- Information needed for cubic Bézier spline evaluation derived from the
  interactivity node’s input values

- Target property value

- Implementation-specific pointer to the `done` output flow of the
  interactivity node that has added this entry

This array is initially empty and its maximum size is
implementation-specific.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If any of the `<parameter>` integer input values is negative or any
    of the `<parameter>` reference input values is null:

    1.  activate the `err` output flow and skip the next steps.

3.  Generate the effective JSON Pointer as described in the previous
    sections.

4.  If the effective JSON Pointer cannot be resolved against the glTF
    asset, if the Object Model type of the resolved property does not
    match the type `T`, or if the property is not mutable,

    1.  activate the `err` output flow and skip the next steps.

5.  If the `duration` input value is NaN, infinite, negative, or greater
    than the maximum property interpolation duration supported by the
    implementation,

    1.  activate the `err` output flow and skip the next steps.

6.  If any component of the `p1` or `p2` input values is NaN or infinite
    or if any of the first components of these input values is negative
    or greater than 1,

    1.  activate the `err` output flow and skip the next steps.

7.  If starting a new pointer interpolation exceeds an
    implementation-specific limit on the maximum number of simultaneous
    property interpolations,

    1.  activate the `err` output flow and skip the next steps.

8.  If the *pointer interpolation state dynamic array* contains an entry
    with the same effective JSON Pointer value,

    1.  remove it from the array.

9.  Using the implicitly-defined end points $`P_0 (0, 0)`$ and
    $`P_3 (1, 1)`$ together with the control points $`P_1`$ and $`P_2`$
    provided via the input values construct a cubic Bézier easing
    function for the $`[0, 1`$\] input range.

10. Add a new entry to the *pointer interpolation state dynamic array*
    filling it with the required information based on the evaluated
    input values.

11. Activate the `out` output flow.

On each tick, for each entry in the *pointer interpolation state dynamic
array*:

1.  Compute the current input progress position *t* as the time passed
    since the interpolation start divided by the interpolation’s
    duration.

2.  If *t* is less than or equal to zero,

    1.  skip the next steps.

3.  If *t* is NaN or greater than or equal to 1,

    1.  set the target property to the target value;

    2.  remove the current entry from the *pointer interpolation state
        dynamic array*;

    3.  activate the `done` output flow linked to the current entry;

    4.  skip the next steps.

4.  Using the cubic Bézier spline information, compute the output
    progress position *q* based on the *t* value. This step implies that
    $`t \in (0; 1)`$.

5.  Set the glTF Asset Object Model property to the new value computed
    as a linear interpolation between the original and the target
    property values using the output progress position *q* as the
    interpolation coefficient. If the glTF Asset Object Model property
    is a quaternion, e.g., `/nodes/0/rotation`, spherical linear
    interpolation **MUST** be used.

> [!NOTE]
> Certain control point values can cause the intermediate output
> progress value to be negative or greater than one. This is not an
> error.

> [!NOTE]
> The `/nodes/{}/weights` pointer defined in the glTF Asset Object Model
> has the `float[]` type that is not supported by this extension. Any
> `pointer/interpolate` node using that pointer would always activate
> only its `err` output flow.

#### Animation Control Operations

##### Animation Start

|  |  |  |
|----|----|----|
| **Operation** | `animation/start` | Start playing an animation |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `ref animation` | Animation reference |
| `float startTime` | Start time in seconds |  |
| `float endTime` | End time in seconds |  |
| `float speed` | Speed multiplier |  |
| **Output flow sockets** | `out` | The flow to be activated if the input values are valid |
| `err` | The flow to be activated if any of the input values is invalid |  |
| `done` | The flow to be activated after the animation ends |  |

This operation starts playing an animation using the specified input
values.

For the purposes of the Animation Control Operations, the concept of
glTF animations is extended to unambiguously map any *requested input
timestamp* $`r`$ to the *effective input timestamp* $`t`$ present in the
glTF animation data as follows.

1.  Let $`T`$ be the maximum value of all animation sampler input
    accessors of the animation. Then, the stored animation data defines
    the animated property values for all *effective input timestamps* in
    the $`[0, T`$\] range.

2.  Let $`r`$ be a scalar value on a timeline infinite in both
    directions, from negative infinity to positive infinity.

3.  If $`T`$ is not equal to zero, let $`s`$ be the current iteration
    number computed as follows: $`s=\begin{cases}
                \left\lceil \dfrac{r-T}{T} \right\rceil & \text{if } r \gt 0 \\
                \left\lfloor \dfrac{r}{T} \right\rfloor & \text{if } r \le 0 \\
               \end{cases}`$

4.  Now for each *requested input timestamp* $`r`$, the corresponding
    *effective input timestamp* is $`t=\begin{cases}
                r - s * T & \text{if } T \ne 0 \\
                0 & \text{if } T=0 \\
               \end{cases}`$

> [!TIP]
> The `/animations/{}/extensions/KHR_interactivity/maxTime` virtual
> property can be used to query the value of $`T`$ for a given
> animation. By setting the `endTime` input value socket to that value,
> the graph can play the animation to completion without statically
> knowing its duration.

This operation has no internal state.

The internal state of an execution graph having one or more
interactivity nodes with the `animation/start` operation includes an
implementation-defined *animation state dynamic array* each element of
which contains the following data:

- Animation reference

- Start time value

- End time value

- Stop time value (see `animation/stopAt`)

- Speed value

- Implementation-specific *entry creation* timestamp value associated
  with the system time when this entry was added

- Implementation-specific *end completion* pointer to the `done` output
  flow of the interactivity node that has added this entry

- Implementation-specific *stop completion* pointer to the `done` output
  flow of the interactivity node that has scheduled its stopping (see
  `animation/stopAt`)

This array is initially empty; its maximum size is
implementation-specific.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If the `animation` input value is not a valid glTF animation
    reference,

    1.  activate the `err` output flow and skip the next steps.

3.  If the `startTime` or `endTime` input values are NaN or if the
    `startTime` input value is infinite,

    1.  activate the `err` output flow and skip the next steps.

4.  If the `speed` input value is NaN, infinite, or less than or equal
    to zero,

    1.  activate the `err` output flow and skip the next steps.

5.  If starting a new animation exceeds an implementation-specific limit
    on the maximum number of active animations or if the referenced glTF
    animation is invalid as determined by the implementation,

    1.  activate the `err` output flow and skip the next steps.

6.  If the *animation state dynamic array* contains an entry with the
    same animation reference,

    1.  remove it from the array; the previously set `done` flows **MUST
        NOT** be activated.

7.  Add a new entry to the *animation state dynamic array* filling it
    with the required information based on the evaluated input values.
    The stop time value **MUST** be set to the end time value and the
    stop completion pointer **MUST** be set to null.

8.  Activate the `out` output flow.

On each asset animation update, for each entry in the *animation state
dynamic array*:

1.  If the *start time* is equal to the *end time*,

    1.  let the requested timestamp $`r`$ be equal to the *start time*;

    2.  compute the effective timestamp $`t`$ from $`r`$ as defined
        above and apply the glTF animation state at the timestamp $`t`$
        to the asset;

    3.  let `endDone` be the *end completion* pointer stored in the
        current animation state entry;

    4.  remove the current animation state entry from the array;

    5.  activate the `done` output flow referenced by the `endDone`
        pointer;

    6.  skip the next steps.

2.  Let the *elapsed time* be the non-negative difference between *entry
    creation* timestamp and the current system time; this step assumes
    that the current system time is not behind the *entry creation*
    timestamp.

3.  Let the *scaled elapsed time* be the product of the *elapsed time*
    and the *animation speed* value; if the *start time* is greater than
    the *end time*, negate the *scaled elapsed time* value.

4.  Let the *current timestamp* be the sum of the *start time* and the
    *scaled elapsed time*.

5.  If the *start time* is less than the *end time*, the *current
    timestamp* is greater than or equal to the *stop time*, the *stop
    time* is greater than or equal to the *start time*, and the *stop
    time* is less than the *end time*; or if the *start time* is greater
    than the *end time*, the *current timestamp* is less than or equal
    to the *stop time*, the *stop time* is less than or equal to the
    *start time*, and the *stop time* is greater than the *end time*:

    1.  let the requested timestamp $`r`$ be equal to the *stop time*;

    2.  compute the effective timestamp $`t`$ from $`r`$ as defined
        above and apply the glTF animation state at the timestamp $`t`$
        to the asset;

    3.  let `stopDone` be the *stop completion* pointer stored in the
        current animation state entry;

    4.  remove the current animation state entry from the array;

    5.  activate the `done` output flow referenced by the `stopDone`
        pointer;

    6.  skip the next steps.

6.  If the *start time* is less than the *end time* and the *current
    timestamp* is greater than or equal to the *end time*; or if the
    *start time* is greater than the *end time* and the *current
    timestamp* is less than or equal to the *end time*:

    1.  let the requested timestamp $`r`$ be equal to the *end time*;

    2.  compute the effective timestamp $`t`$ from $`r`$ as defined
        above and apply the glTF animation state at the timestamp $`t`$
        to the asset;

    3.  let `endDone` be the end completion pointer stored in the
        current animation state entry;

    4.  remove the current animation state entry from the array;

    5.  activate the `done` output flow referenced by the `endDone`
        pointer;

    6.  skip the next steps.

7.  Let the requested timestamp $`r`$ be equal to the *current
    timestamp*.

8.  Compute the effective timestamp $`t`$ from $`r`$ as defined above
    and apply the glTF animation state at the timestamp $`t`$ to the
    asset.

If two or more active animations target the same glTF property, it
becomes undefined and remains undefined as long as the number of active
animations affecting it is greater than one.

> [!NOTE]
> Let’s say an asset has two animations that target position of the glTF
> node zero. The first animation lasts 15 seconds and the second
> animation lasts 5 seconds. The graph starts the first animation, waits
> 5 seconds, then it starts the second animation. Both animations are
> played to completion once.
>
> During the first 5 seconds, the position of the glTF node zero is
> well-defined. It is repeatedly updated by the first animation and
> could be reliably queried with a `pointer/get` operation.
>
> During the next 5 seconds (i.e., when both animations are active) the
> position of the glTF node zero is undefined. Since both animations try
> to update it at the same time, querying the property with a
> `pointer/get` operation could return arbitrary values. However, using
> a `pointer/set` operation on that property would make it well-defined
> until the next animation update.
>
> During the last 5 seconds, the position of the glTF node zero is
> well-defined again.

##### Animation Stop

|  |  |  |
|----|----|----|
| **Operation** | `animation/stop` | Immediately stop a playing animation |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `ref animation` | Animation reference |
| **Output flow sockets** | `out` | The flow to be activated if the animation reference is valid |
| `err` | The flow to be activated if the animation reference is invalid |  |

This operation stops a playing animation.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If the `animation` input value is not a valid glTF animation
    reference,

    1.  activate the `err` output flow and skip the next steps.

3.  If the *animation state dynamic array* exists and contains an entry
    with the same animation reference,

    1.  remove it from the array and stop the playing animation. The
        animated properties **MUST** keep their current values and the
        previously associated `done` flows **MUST NOT** be activated.

4.  Activate the `out` output flow.

##### Animation Stop At

|  |  |  |
|----|----|----|
| **Operation** | `animation/stopAt` | Schedule stopping a playing animation |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `ref animation` | Animation reference |
| `float stopTime` | Stop time in seconds |  |
| **Output flow sockets** | `out` | The flow to be activated if the input values are valid |
| `err` | The flow to be activated if any of the input values is invalid |  |
| `done` | The flow to be activated after the animation stops |  |

This operation schedules stopping a playing animation at the specified
time.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If the `animation` input value is not a valid glTF animation
    reference,

    1.  activate the `err` output flow and skip the next steps.

3.  If the `stopTime` input value is NaN,

    1.  activate the `err` output flow and skip the next steps.

4.  If the *animation state dynamic array* exists and does contain an
    entry with the same animation index,

    1.  update the entry’s *stop completion* pointer to the `done`
        output flow of this interactivity node;

    2.  update the entry’s *stop time* to the `stopTime` input value.

5.  Activate the `out` output flow.

### Event Operations

#### Lifecycle Event Operations

##### On Start

|  |  |  |
|----|----|----|
| **Operation** | `event/onStart` | Start event |
| **Output value sockets** | `ref event` | The event reference |
| **Output flow sockets** | `out` | The flow to be activated when the start event happens |

Interactivity nodes with this operation are activated when all glTF
asset resources are loaded and ready for rendering and interactions.

The internal state of this operation consists of the event reference
value initialized to null. It **MUST** be set to the reference to the
implementation-specific event representation before the `out` output
flow is activated.

If multiple interactivity nodes with this operation exist in the graph,
they **MUST** be activated sequentially in the order they appear in
JSON. All interactivity nodes with this operation **MUST** return the
same event reference on activation.

##### On Tick

|  |  |  |
|----|----|----|
| **Operation** | `event/onTick` | Tick event |
| **Output value sockets** | `float timeSinceStart` | Relative time in seconds since the graph execution start |
| `float timeSinceLastTick` | Relative time in seconds since the last tick occurred |  |
| `ref event` | The event reference |  |
| **Output flow sockets** | `out` | The flow to be activated when the tick event happens |

Interactivity nodes with this operation are activated when a tick
occurs. There will be at most one tick per rendered frame, which
**SHOULD** align with frame time, but there are no guarantees of time
elapsed between ticks.

The internal state of this operation consists of two floating-point time
values initialized to NaN and the event reference value initialized to
null. They **MUST** be set to their effective values before the `out`
output flow is activated.

The first activation of an interactivity node with this operation
**MUST** happen after activating all interactivity nodes with the
`event/onStart` operation if the latter is present in the graph.

On the very first tick event, the `timeSinceStart` output value **MUST**
be set to zero and the `timeSinceLastTick` output value **MUST** remain
NaN.

If multiple interactivity nodes with this operation exist in the graph,
they **MUST** be activated sequentially in the order they appear in JSON
and they **MUST** have the same output values within the same tick.

#### Event Control Operations

##### Stop Propagation

|  |  |  |
|----|----|----|
| **Operation** | `event/stopPropagation` | Stop event propagation |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `bool stopImmediate` | Whether to stop event propagation to the subsequent interactivity nodes |
| `ref event` | Event reference |  |
| **Output flow sockets** | `out` | The flow to be activated after executing this operation |

This operation prevents further activations of event handlers associated
with the event reference.

If the `stopImmediate` input value is false, this operation only
prevents transitive activations of event handlers, for example, handlers
activated by propagating the event through the scene graph.

> [!NOTE]
> The events defined in this specification, i.e., `event/onStart` and
> `event/onTick`, do not cause any transitive activations.

If the `stopImmediate` input value is true, this operation prevents
transitive activations of event handlers and the activations of the
event handlers for the same event defined in the behavior graph that
have not been activated yet.

> [!NOTE]
> Let’s say a behavior graph contains two interactivity nodes with the
> `event/onTick` operation and the first interactivity node
> unconditionally activates an interactivity node with the
> `event/stopPropagation` operation passing the event reference and
> setting the `stopImmediate` input value to true. Then the second
> interactivity node with the `event/onTick` operation is never
> activated.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  If the `event` input value is not a valid event reference,

    1.  activate the `out` output flow and skip the next steps.

3.  Cancel all pending transitive activations of the interactivity event
    nodes associated with the `event` input value.

4.  If the `stopImmediate` input value is true,

    1.  cancel all pending immediate activations of the interactivity
        event nodes associated with the `event` input value.

5.  Activate the `out` output flow.

#### Custom Event Operations

##### Receive

|  |  |  |
|----|----|----|
| **Operation** | `event/receive` | Receive a custom event |
| **Configuration** | `int event` | The custom event index |
| **Output value sockets** | `<custom>` | Output values defined by the custom event |
| `ref event` | The event reference |  |
| **Output flow sockets** | `out` | The flow to be activated when the custom event happens |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value sockets.

Interactivity nodes with this operation are activated when a custom
event specified by the `event` configuration value occurs. The types,
ids, and semantics of the output value sockets are defined by the custom
event index.

The `event` configuration value **MUST** be non-negative and less than
the total number of custom event definitions, otherwise the
interactivity node is invalid and the graph **MUST** be rejected.

The internal state of this operation consists of all output value
sockets initialized to [type-default](#variables-types) values or to the
initial values defined by the custom event index and the event reference
value initialized to null. If the event is originated by an external
environment, output values not set by the external environment **MUST**
be reset to type-default or initial values on each interactivity node
activation.

> [!NOTE]
> Let’s say an event has two value sockets: `a` and `b`; before the
> first activation, they have initial or type-default values. Let’s say
> the external environment generates this event and sets only the output
> value `a`. The output value `b` then retains its initial or
> type-default value. Now if the external environment generates this
> event again but sets only the output value `b`, the output value `a`
> is reset to its initial or type-default value.

If multiple interactivity nodes with this operation and the same event
index exist in the graph, they **MUST** be activated sequentially in the
order they appear in JSON and they **MUST** have the same output values
within the same event occurrence.

##### Send

|  |  |  |
|----|----|----|
| **Operation** | `event/send` | Send a custom event |
| **Configuration** | `int event` | The custom event index |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `<custom>` | Input values defined by the custom event |
| **Output flow sockets** | `out` | The flow to be activated after sending the event |

> [!CAUTION]
> This operation does not have a default configuration.

> [!CAUTION]
> The configuration of this operation affects its value sockets.

This operation sends a custom event specified by the `event`
configuration value. The types and ids of the input value sockets are
defined by the custom event index.

> [!TIP]
> If the graph needs to know whether the event has been received and/or
> processed by an external environment, the latter could send another
> event in response.

The `event` configuration value **MUST** be non-negative and less than
the total number of custom event definitions, otherwise the
interactivity node is invalid and the graph **MUST** be rejected.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  Send the custom event.

3.  Activate the `out` output flow.

### Debug Operations

#### Debug Output Operations

##### Log

|  |  |  |
|----|----|----|
| **Operation** | `debug/log` | Output a debug message |
| **Configuration** | `int severity` | Message severity |
| `string message` | Message template |  |
| **Input flow sockets** | `in` | The entry flow into this operation |
| **Input value sockets** | `<any> <parameter>` | Zero or more message template parameters to be evaluated at runtime; input value socket ids correspond to the message substrings wrapped with curly brackets (`{}`) |
| **Output flow sockets** | `out` | The flow to be activated after the message was logged |

> [!CAUTION]
> The configuration of this operation affects its value sockets.

This operation builds a debug message from the specified template string
and input socket values as described below and outputs the message to
the user in an implementation-defined manner.

The `severity` configuration value is intended for filtering messages
based on the implementation configuration. The `message` configuration
value contains the debug message template string that defines the
user-facing text message and input value socket ids (if any).

The value socket ids are substrings of the `message` value wrapped with
curly brackets (`{}`); they are extracted as described below. Literal
curly brackets present in the message template string **MUST** be
doubled.

The type `any` represents any value socket type including custom types.
This operation implies that all value types have implementation-defined
string representations.

In the default configuration, the `severity` configuration value is
zero, the `message` configuration string is empty, and the operation has
no input value sockets.

If the `severity` configuration property is not provided by the behavior
graph, if it is not a literal number, or if its value is not exactly
representable as a 32-bit signed integer, the default configuration
**MUST** be used.

> [!TIP]
> The integer representation check is implementable in ECMAScript via
> the following expression:
>
> ``` js
> s === (s | 0)
> ```

If the `message` configuration property is not provided by the behavior
graph, if it is not a literal string, or if its value is not
syntactically valid as described below, the default configuration
**MUST** be used.

The following procedure outputs input value socket id locations within
the `message` configuration string and returns whether the string is
syntactically valid:

1.  Let *state* be a temporary integer variable initialized to zero.
    During the procedure execution, its value will always be one of 0,
    1, 2, or 3.

2.  Let *paramStart* be a temporary integer variable initialized to
    unspecified value.

3.  Let `M[i]` be the character (Unicode code point) of the `message`
    configuration string at the position `i` (zero-based).

4.  For `i` from zero (inclusive) to the `message` length (exclusive),
    do:

    1.  If `M[i]` is `"{"` (without quotes):

        1.  If *state* is 0, set *state* to 1;

        2.  else if *state* is 1, set *state* to 0;

        3.  else (if *state* is 2 or 3) return false.

    2.  Else if `M[i]` is `"}"` (without quotes):

        1.  If *state* is 0, set *state* to 3;

        2.  else if *state* is 3, set *state* to 0;

        3.  else if *state* is 2,

            1.  output the (*paramStart*, `i`) tuple as the inclusive
                range defining the template parameter location in the
                `message` string;

            2.  set *state* to 0;

        4.  else (if *state* is 1) return false.

    3.  Else if `M[i]` is neither `"{"` nor `"}"` (without quotes):

        1.  If *state* is 1,

            1.  set *paramStart* to `i - 1`;

            2.  set *state* to 2;

        2.  else if *state* is 3, return false.

5.  If *state* is not 0, return false.

6.  Return true.

If the procedure above returns false, the `message` configuration string
is invalid and the default configuration is used. If the procedure above
returns true, the input value socket ids match the substrings identified
by the template parameter locations with curly brackets removed.

If the interactivity node’s JSON object does not contain all input value
sockets generated by the procedure above, the interactivity node is
invalid and the graph **MUST** be rejected.

Extra input value sockets with ids not present in the output of the
procedure above do not affect the interactivity node’s operation and
validation but they still **MUST** have valid value sources.

This operation has no internal state.

When the `in` input flow is activated:

1.  Evaluate all input values.

2.  Generate the effective message string as follows.

    1.  Let *M* be a copy of the `message` configuration value.

    2.  For each element of the template parameter array taken in the
        descending order of parameter substring locations:

        1.  Convert the corresponding input socket value to its string
            representation.

        2.  If the string representation of the input socket value
            contains curly brackets, they **MUST** be doubled.

        3.  Update *M* by replacing the template parameter substring, as
            identified by the template parameter location, with the
            string representation of the corresponding input value
            socket. Note that the same template parameter **MAY** appear
            at multiple locations.

    3.  Update *M* by replacing all occurrences of the `"{{"` substring
        in it with `"{"` (without quotes).

    4.  Update *M* by replacing all occurrences of the `"}}"` substring
        in it with `"}"` (without quotes).

3.  Output *M* as the effective message string.

4.  Activate the `out` output flow.


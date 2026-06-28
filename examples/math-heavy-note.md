# Math-Heavy Markdown Preview

This note is designed to show why rendering Markdown through a PDF pipeline is
useful inside a terminal file manager. Plain Markdown previewers can show the
source text, but equations like $E = mc^2$ and $\nabla \cdot \mathbf{E} =
\rho / \epsilon_0$ are much easier to read once they are typeset.

## Diffusion From A Point Source

For a particle released at the origin, the one-dimensional diffusion equation

$$
\frac{\partial p(x,t)}{\partial t}
= D \frac{\partial^2 p(x,t)}{\partial x^2}
$$

has the normalized Green's function

$$
p(x,t) =
\frac{1}{\sqrt{4 \pi D t}}
\exp\left(-\frac{x^2}{4Dt}\right).
$$

The second moment grows linearly:

$$
\begin{aligned}
\left\langle x^2(t) \right\rangle
&= \int_{-\infty}^{\infty} x^2 p(x,t) \, dx \\
&= 2Dt.
\end{aligned}
$$

## A Small Linear System

Markdown notes often mix prose, tables, and matrix equations. For example, a
three-node spring chain can be written as

$$
\mathbf{K}\mathbf{u} =
\begin{bmatrix}
 2k & -k &  0 \\
-k  & 2k & -k \\
 0  & -k & 2k
\end{bmatrix}
\begin{bmatrix}
u_1 \\
u_2 \\
u_3
\end{bmatrix}
=
\begin{bmatrix}
f_1 \\
f_2 \\
f_3
\end{bmatrix}.
$$

| Symbol | Meaning | Example value |
| --- | --- | ---: |
| $D$ | diffusion coefficient | $0.10$ |
| $k$ | spring constant | $25$ |
| $\Delta t$ | simulation step | $10^{-3}$ |

## Code And Result

The same note can still include code blocks:

```python
import numpy as np

D = 0.10
t = np.linspace(0.01, 2.0, 200)
msd = 2 * D * t
```

and then summarize the result in text:

$$
\mathrm{MSD}(t) = 2Dt,
\qquad
\frac{d}{dt}\mathrm{MSD}(t) = 2D.
$$


---
title: TeXMath with SHTML
author: Iris Lennon
date: 2026-06-04
tags: shtml, haskell
---

(h1 "TeXMath Test with SHTML")

(p "Inline math: " (@ (LaTeX "E = mc^2")) " via texmath.")

(p "More inline: " (@ (LaTeX "\int_a^b f(x)\,dx = F(b) - F(a)")) ".")

(h2 "Display Math")

(p "The quadratic formula:")

(@ (LaTeX [display "true"] "x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"))

(p "A more complex example:")

(@ (LaTeX [display "true"] "\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"))

(p "A more complex example:" (@ (LaTeX [display "flash"] "\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}")))

(h2 "Matrix")

(@ (LaTeX [display "true"] "\begin{pmatrix} a & b \\ c & d \end{pmatrix}"))

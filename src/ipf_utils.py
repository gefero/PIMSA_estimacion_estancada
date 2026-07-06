# -*- coding: utf-8 -*-
"""Utilidades compartidas para la estimación IPF (usado por 015 y 016)."""

import numpy as np

# Niveles canónicos de las tres dimensiones, en orden fijo
CAL = ["1.Baja", "2.Media", "3.Alta"]
OCU = ["1.Asalariado_patr", "3.TCP_fliares"]
RAM = ["1.Agro", "2.No_agro"]


def ipf3_targets(t12, t13, t23, shape=(3, 2, 2), iters=5000, tol=1e-12):
    """IPF trivariado con seed uniforme y tres targets bivariados.

    t12: calif x ocup ; t13: calif x rama ; t23: ocup x rama.
    Devuelve la trivariada ajustada (misma escala que los targets).
    """
    x = np.ones(shape)
    x = x / x.sum() * t12.sum()
    for _ in range(iters):
        m = x.sum(2)
        x *= np.divide(t12, m, out=np.zeros_like(t12), where=m > 0)[:, :, None]
        m = x.sum(1)
        x *= np.divide(t13, m, out=np.zeros_like(t13), where=m > 0)[:, None, :]
        m = x.sum(0)
        x *= np.divide(t23, m, out=np.zeros_like(t23), where=m > 0)[None, :, :]
        if np.abs(x.sum(2) - t12).max() < tol:
            break
    return x


def ipf3_selftest(joint, iters=2000, tol=1e-12):
    """IPF cuyos targets son los tres márgenes bivariados de `joint`.

    Mide el error atribuible únicamente al supuesto de no-interacción
    de tercer orden (targets perfectamente consistentes por construcción).
    """
    return ipf3_targets(joint.sum(2), joint.sum(1), joint.sum(0),
                        shape=joint.shape, iters=iters, tol=tol)

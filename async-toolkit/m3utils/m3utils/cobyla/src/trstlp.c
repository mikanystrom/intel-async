/* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. */
/* SPDX-License-Identifier: Apache-2.0 */

/* trstlp.f -- translated by f2c (version 20200916).
   You must link the resulting object file with libf2c:
	on Microsoft Windows system, link with libf2c.lib;
	on Linux or Unix systems, link with .../path/to/libf2c.a -lm
	or, if you install libf2c.a in a standard place, with -lf2c -lm
	-- in that order, at the end of the command line, as in
		cc *.o -lf2c -lm
	Source for libf2c is in /netlib/f2c/libf2c.zip, e.g.,

		http://www.netlib.org/f2c/libf2c.zip
*/

#include "f2c.h"

/* Subroutine */ int trstlp_(integer *n, integer *m, doublereal *a, 
	doublereal *b, doublereal *rho, doublereal *dx, integer *ifull, 
	integer *iact, doublereal *z__, doublereal *zdota, doublereal *vmultc,
	 doublereal *sdirn, doublereal *dxnew, doublereal *vmultd)
{
    /* System generated locals */
    integer a_dim1, a_offset, z_dim1, z_offset, i__1, i__2;
    doublereal d__1, d__2;

    /* Builtin functions */
    double sqrt(doublereal);

    /* Local variables */
    static integer i__, j, k;
    static doublereal dd;
    static integer kk;
    static doublereal sd;
    static integer kl, kp, kw;
    static doublereal sp, ss, sum, tot, acca, accb, beta;
    static integer nact, icon, mcon;
    static doublereal temp, step;
    static integer iout __attribute__((unused));
    static doublereal alpha, tempa;
    static integer isave;
    static doublereal spabs;
    static integer nactx;
    static doublereal ratio, vsave, zdotv, zdotw, resold, zdvabs, zdwabs, 
	    sumabs, resmax, optold;
    static integer icount;
    static doublereal optnew, stpful;


/*     This subroutine calculates an N-component vector DX by applying the */
/*     following two stages. In the first stage, DX is set to the shortest */
/*     vector that minimizes the greatest violation of the constraints */
/*       A(1,K)*DX(1)+A(2,K)*DX(2)+...+A(N,K)*DX(N) .GE. B(K), K=2,3,...,M, */
/*     subject to the Euclidean length of DX being at most RHO. If its length is */
/*     strictly less than RHO, then we use the resultant freedom in DX to */
/*     minimize the objective function */
/*              -A(1,M+1)*DX(1)-A(2,M+1)*DX(2)-...-A(N,M+1)*DX(N) */
/*     subject to no increase in any greatest constraint violation. This */
/*     notation allows the gradient of the objective function to be regarded as */
/*     the gradient of a constraint. Therefore the two stages are distinguished */
/*     by MCON .EQ. M and MCON .GT. M respectively. It is possible that a */
/*     degeneracy may prevent DX from attaining the target length RHO. Then the */
/*     value IFULL=0 would be set, but usually IFULL=1 on return. */

/*     In general NACT is the number of constraints in the active set and */
/*     IACT(1),...,IACT(NACT) are their indices, while the remainder of IACT */
/*     contains a permutation of the remaining constraint indices. Further, Z is */
/*     an orthogonal matrix whose first NACT columns can be regarded as the */
/*     result of Gram-Schmidt applied to the active constraint gradients. For */
/*     J=1,2,...,NACT, the number ZDOTA(J) is the scalar product of the J-th */
/*     column of Z with the gradient of the J-th active constraint. DX is the */
/*     current vector of variables and here the residuals of the active */
/*     constraints should be zero. Further, the active constraints have */
/*     nonnegative Lagrange multipliers that are held at the beginning of */
/*     VMULTC. The remainder of this vector holds the residuals of the inactive */
/*     constraints at DX, the ordering of the components of VMULTC being in */
/*     agreement with the permutation of the indices of the constraints that is */
/*     in IACT. All these residuals are nonnegative, which is achieved by the */
/*     shift RESMAX that makes the least residual zero. */

/*     Initialize Z and some other variables. The value of RESMAX will be */
/*     appropriate to DX=0, while ICON will be the index of a most violated */
/*     constraint if RESMAX is positive. Usually during the first stage the */
/*     vector SDIRN gives a search direction that reduces all the active */
/*     constraint violations by one simultaneously. */

    /* Parameter adjustments */
    z_dim1 = *n;
    z_offset = 1 + z_dim1;
    z__ -= z_offset;
    a_dim1 = *n;
    a_offset = 1 + a_dim1;
    a -= a_offset;
    --b;
    --dx;
    --iact;
    --zdota;
    --vmultc;
    --sdirn;
    --dxnew;
    --vmultd;

    /* Function Body */
    *ifull = 1;
    mcon = *m;
    nact = 0;
    resmax = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
	i__2 = *n;
	for (j = 1; j <= i__2; ++j) {
/* L10: */
	    z__[i__ + j * z_dim1] = 0.f;
	}
	z__[i__ + i__ * z_dim1] = 1.f;
/* L20: */
	dx[i__] = 0.f;
    }
    if (*m >= 1) {
	i__1 = *m;
	for (k = 1; k <= i__1; ++k) {
	    if (b[k] > resmax) {
		resmax = b[k];
		icon = k;
	    }
/* L30: */
	}
	i__1 = *m;
	for (k = 1; k <= i__1; ++k) {
	    iact[k] = k;
/* L40: */
	    vmultc[k] = resmax - b[k];
	}
    }
    if (resmax == 0.f) {
	goto L480;
    }
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L50: */
	sdirn[i__] = 0.f;
    }

/*     End the current stage of the calculation if 3 consecutive iterations */
/*     have either failed to reduce the best calculated value of the objective */
/*     function or to increase the number of active constraints since the best */
/*     value was calculated. This strategy prevents cycling, but there is a */
/*     remote possibility that it will cause premature termination. */

L60:
    optold = 0.f;
    icount = 0;
L70:
    if (mcon == *m) {
	optnew = resmax;
    } else {
	optnew = 0.f;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
/* L80: */
	    optnew -= dx[i__] * a[i__ + mcon * a_dim1];
	}
    }
    if (icount == 0 || optnew < optold) {
	optold = optnew;
	nactx = nact;
	icount = 3;
    } else if (nact > nactx) {
	nactx = nact;
	icount = 3;
    } else {
	--icount;
	if (icount == 0) {
	    goto L490;
	}
    }

/*     If ICON exceeds NACT, then we add the constraint with index IACT(ICON) to */
/*     the active set. Apply Givens rotations so that the last N-NACT-1 columns */
/*     of Z are orthogonal to the gradient of the new constraint, a scalar */
/*     product being set to zero if its nonzero value could be due to computer */
/*     rounding errors. The array DXNEW is used for working space. */

    if (icon <= nact) {
	goto L260;
    }
    kk = iact[icon];
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L90: */
	dxnew[i__] = a[i__ + kk * a_dim1];
    }
    tot = 0.f;
    k = *n;
L100:
    if (k > nact) {
	sp = 0.f;
	spabs = 0.f;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
	    temp = z__[i__ + k * z_dim1] * dxnew[i__];
	    sp += temp;
/* L110: */
	    spabs += abs(temp);
	}
	acca = spabs + abs(sp) * .1f;
	accb = spabs + abs(sp) * .2f;
	if (spabs >= acca || acca >= accb) {
	    sp = 0.f;
	}
	if (tot == 0.f) {
	    tot = sp;
	} else {
	    kp = k + 1;
	    temp = sqrt(sp * sp + tot * tot);
	    alpha = sp / temp;
	    beta = tot / temp;
	    tot = temp;
	    i__1 = *n;
	    for (i__ = 1; i__ <= i__1; ++i__) {
		temp = alpha * z__[i__ + k * z_dim1] + beta * z__[i__ + kp * 
			z_dim1];
		z__[i__ + kp * z_dim1] = alpha * z__[i__ + kp * z_dim1] - 
			beta * z__[i__ + k * z_dim1];
/* L120: */
		z__[i__ + k * z_dim1] = temp;
	    }
	}
	--k;
	goto L100;
    }

/*     Add the new constraint if this can be done without a deletion from the */
/*     active set. */

    if (tot != 0.f) {
	++nact;
	zdota[nact] = tot;
	vmultc[icon] = vmultc[nact];
	vmultc[nact] = 0.f;
	goto L210;
    }

/*     The next instruction is reached if a deletion has to be made from the */
/*     active set in order to make room for the new active constraint, because */
/*     the new constraint gradient is a linear combination of the gradients of */
/*     the old active constraints. Set the elements of VMULTD to the multipliers */
/*     of the linear combination. Further, set IOUT to the index of the */
/*     constraint to be deleted, but branch if no suitable index can be found. */

    ratio = -1.f;
    k = nact;
L130:
    zdotv = 0.f;
    zdvabs = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
	temp = z__[i__ + k * z_dim1] * dxnew[i__];
	zdotv += temp;
/* L140: */
	zdvabs += abs(temp);
    }
    acca = zdvabs + abs(zdotv) * .1f;
    accb = zdvabs + abs(zdotv) * .2f;
    if (zdvabs < acca && acca < accb) {
	temp = zdotv / zdota[k];
	if (temp > 0.f && iact[k] <= *m) {
	    tempa = vmultc[k] / temp;
	    if (ratio < 0.f || tempa < ratio) {
		ratio = tempa;
		iout = k;
	    }
	}
	if (k >= 2) {
	    kw = iact[k];
	    i__1 = *n;
	    for (i__ = 1; i__ <= i__1; ++i__) {
/* L150: */
		dxnew[i__] -= temp * a[i__ + kw * a_dim1];
	    }
	}
	vmultd[k] = temp;
    } else {
	vmultd[k] = 0.f;
    }
    --k;
    if (k > 0) {
	goto L130;
    }
    if (ratio < 0.f) {
	goto L490;
    }

/*     Revise the Lagrange multipliers and reorder the active constraints so */
/*     that the one to be replaced is at the end of the list. Also calculate the */
/*     new value of ZDOTA(NACT) and branch if it is not acceptable. */

    i__1 = nact;
    for (k = 1; k <= i__1; ++k) {
/* L160: */
/* Computing MAX */
	d__1 = 0.f, d__2 = vmultc[k] - ratio * vmultd[k];
	vmultc[k] = (real) max(d__1,d__2);
    }
    if (icon < nact) {
	isave = iact[icon];
	vsave = vmultc[icon];
	k = icon;
L170:
	kp = k + 1;
	kw = iact[kp];
	sp = 0.f;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
/* L180: */
	    sp += z__[i__ + k * z_dim1] * a[i__ + kw * a_dim1];
	}
/* Computing 2nd power */
	d__1 = zdota[kp];
	temp = sqrt(sp * sp + d__1 * d__1);
	alpha = zdota[kp] / temp;
	beta = sp / temp;
	zdota[kp] = alpha * zdota[k];
	zdota[k] = temp;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
	    temp = alpha * z__[i__ + kp * z_dim1] + beta * z__[i__ + k * 
		    z_dim1];
	    z__[i__ + kp * z_dim1] = alpha * z__[i__ + k * z_dim1] - beta * 
		    z__[i__ + kp * z_dim1];
/* L190: */
	    z__[i__ + k * z_dim1] = temp;
	}
	iact[k] = kw;
	vmultc[k] = vmultc[kp];
	k = kp;
	if (k < nact) {
	    goto L170;
	}
	iact[k] = isave;
	vmultc[k] = vsave;
    }
    temp = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L200: */
	temp += z__[i__ + nact * z_dim1] * a[i__ + kk * a_dim1];
    }
    if (temp == 0.f) {
	goto L490;
    }
    zdota[nact] = temp;
    vmultc[icon] = 0.f;
    vmultc[nact] = ratio;

/*     Update IACT and ensure that the objective function continues to be */
/*     treated as the last active constraint when MCON>M. */

L210:
    iact[icon] = iact[nact];
    iact[nact] = kk;
    if (mcon > *m && kk != mcon) {
	k = nact - 1;
	sp = 0.f;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
/* L220: */
	    sp += z__[i__ + k * z_dim1] * a[i__ + kk * a_dim1];
	}
/* Computing 2nd power */
	d__1 = zdota[nact];
	temp = sqrt(sp * sp + d__1 * d__1);
	alpha = zdota[nact] / temp;
	beta = sp / temp;
	zdota[nact] = alpha * zdota[k];
	zdota[k] = temp;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
	    temp = alpha * z__[i__ + nact * z_dim1] + beta * z__[i__ + k * 
		    z_dim1];
	    z__[i__ + nact * z_dim1] = alpha * z__[i__ + k * z_dim1] - beta * 
		    z__[i__ + nact * z_dim1];
/* L230: */
	    z__[i__ + k * z_dim1] = temp;
	}
	iact[nact] = iact[k];
	iact[k] = kk;
	temp = vmultc[k];
	vmultc[k] = vmultc[nact];
	vmultc[nact] = temp;
    }

/*     If stage one is in progress, then set SDIRN to the direction of the next */
/*     change to the current vector of variables. */

    if (mcon > *m) {
	goto L320;
    }
    kk = iact[nact];
    temp = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L240: */
	temp += sdirn[i__] * a[i__ + kk * a_dim1];
    }
    temp += -1.f;
    temp /= zdota[nact];
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L250: */
	sdirn[i__] -= temp * z__[i__ + nact * z_dim1];
    }
    goto L340;

/*     Delete the constraint that has the index IACT(ICON) from the active set. */

L260:
    if (icon < nact) {
	isave = iact[icon];
	vsave = vmultc[icon];
	k = icon;
L270:
	kp = k + 1;
	kk = iact[kp];
	sp = 0.f;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
/* L280: */
	    sp += z__[i__ + k * z_dim1] * a[i__ + kk * a_dim1];
	}
/* Computing 2nd power */
	d__1 = zdota[kp];
	temp = sqrt(sp * sp + d__1 * d__1);
	alpha = zdota[kp] / temp;
	beta = sp / temp;
	zdota[kp] = alpha * zdota[k];
	zdota[k] = temp;
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
	    temp = alpha * z__[i__ + kp * z_dim1] + beta * z__[i__ + k * 
		    z_dim1];
	    z__[i__ + kp * z_dim1] = alpha * z__[i__ + k * z_dim1] - beta * 
		    z__[i__ + kp * z_dim1];
/* L290: */
	    z__[i__ + k * z_dim1] = temp;
	}
	iact[k] = kk;
	vmultc[k] = vmultc[kp];
	k = kp;
	if (k < nact) {
	    goto L270;
	}
	iact[k] = isave;
	vmultc[k] = vsave;
    }
    --nact;

/*     If stage one is in progress, then set SDIRN to the direction of the next */
/*     change to the current vector of variables. */

    if (mcon > *m) {
	goto L320;
    }
    temp = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L300: */
	temp += sdirn[i__] * z__[i__ + (nact + 1) * z_dim1];
    }
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L310: */
	sdirn[i__] -= temp * z__[i__ + (nact + 1) * z_dim1];
    }
    goto L340;

/*     Pick the next search direction of stage two. */

L320:
    temp = 1.f / zdota[nact];
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L330: */
	sdirn[i__] = temp * z__[i__ + nact * z_dim1];
    }

/*     Calculate the step to the boundary of the trust region or take the step */
/*     that reduces RESMAX to zero. The two statements below that include the */
/*     factor 1.0E-6 prevent some harmless underflows that occurred in a test */
/*     calculation. Further, we skip the step if it could be zero within a */
/*     reasonable tolerance for computer rounding errors. */

L340:
    dd = *rho * *rho;
    sd = 0.f;
    ss = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
	if ((d__1 = dx[i__], abs(d__1)) >= *rho * 1e-6f) {
/* Computing 2nd power */
	    d__2 = dx[i__];
	    dd -= d__2 * d__2;
	}
	sd += dx[i__] * sdirn[i__];
/* L350: */
/* Computing 2nd power */
	d__1 = sdirn[i__];
	ss += d__1 * d__1;
    }
    if (dd <= 0.f) {
	goto L490;
    }
    temp = sqrt(ss * dd);
    if (abs(sd) >= temp * 1e-6f) {
	temp = sqrt(ss * dd + sd * sd);
    }
    stpful = dd / (temp + sd);
    step = stpful;
    if (mcon == *m) {
	acca = step + resmax * .1f;
	accb = step + resmax * .2f;
	if (step >= acca || acca >= accb) {
	    goto L480;
	}
	step = (real) min(step,resmax);
    }

/*     Set DXNEW to the new variables if STEP is the steplength, and reduce */
/*     RESMAX to the corresponding maximum residual if stage one is being done. */
/*     Because DXNEW will be changed during the calculation of some Lagrange */
/*     multipliers, it will be restored to the following value later. */

    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L360: */
	dxnew[i__] = dx[i__] + step * sdirn[i__];
    }
    if (mcon == *m) {
	resold = resmax;
	resmax = 0.f;
	i__1 = nact;
	for (k = 1; k <= i__1; ++k) {
	    kk = iact[k];
	    temp = b[kk];
	    i__2 = *n;
	    for (i__ = 1; i__ <= i__2; ++i__) {
/* L370: */
		temp -= a[i__ + kk * a_dim1] * dxnew[i__];
	    }
	    resmax = (real) max(resmax,temp);
/* L380: */
	}
    }

/*     Set VMULTD to the VMULTC vector that would occur if DX became DXNEW. A */
/*     device is included to force VMULTD(K)=0.0 if deviations from this value */
/*     can be attributed to computer rounding errors. First calculate the new */
/*     Lagrange multipliers. */

    k = nact;
L390:
    zdotw = 0.f;
    zdwabs = 0.f;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
	temp = z__[i__ + k * z_dim1] * dxnew[i__];
	zdotw += temp;
/* L400: */
	zdwabs += abs(temp);
    }
    acca = zdwabs + abs(zdotw) * .1f;
    accb = zdwabs + abs(zdotw) * .2f;
    if (zdwabs >= acca || acca >= accb) {
	zdotw = 0.f;
    }
    vmultd[k] = zdotw / zdota[k];
    if (k >= 2) {
	kk = iact[k];
	i__1 = *n;
	for (i__ = 1; i__ <= i__1; ++i__) {
/* L410: */
	    dxnew[i__] -= vmultd[k] * a[i__ + kk * a_dim1];
	}
	--k;
	goto L390;
    }
    if (mcon > *m) {
/* Computing MAX */
	d__1 = 0.f, d__2 = vmultd[nact];
	vmultd[nact] = (real) max(d__1,d__2);
    }

/*     Complete VMULTC by finding the new constraint residuals. */

    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L420: */
	dxnew[i__] = dx[i__] + step * sdirn[i__];
    }
    if (mcon > nact) {
	kl = nact + 1;
	i__1 = mcon;
	for (k = kl; k <= i__1; ++k) {
	    kk = iact[k];
	    sum = resmax - b[kk];
	    sumabs = resmax + (d__1 = b[kk], abs(d__1));
	    i__2 = *n;
	    for (i__ = 1; i__ <= i__2; ++i__) {
		temp = a[i__ + kk * a_dim1] * dxnew[i__];
		sum += temp;
/* L430: */
		sumabs += abs(temp);
	    }
	    acca = sumabs + abs(sum) * .1f;
	    accb = sumabs + abs(sum) * .2f;
	    if (sumabs >= acca || acca >= accb) {
		sum = 0.f;
	    }
/* L440: */
	    vmultd[k] = sum;
	}
    }

/*     Calculate the fraction of the step from DX to DXNEW that will be taken. */

    ratio = 1.f;
    icon = 0;
    i__1 = mcon;
    for (k = 1; k <= i__1; ++k) {
	if (vmultd[k] < 0.f) {
	    temp = vmultc[k] / (vmultc[k] - vmultd[k]);
	    if (temp < ratio) {
		ratio = temp;
		icon = k;
	    }
	}
/* L450: */
    }

/*     Update DX, VMULTC and RESMAX. */

    temp = 1.f - ratio;
    i__1 = *n;
    for (i__ = 1; i__ <= i__1; ++i__) {
/* L460: */
	dx[i__] = temp * dx[i__] + ratio * dxnew[i__];
    }
    i__1 = mcon;
    for (k = 1; k <= i__1; ++k) {
/* L470: */
/* Computing MAX */
	d__1 = 0.f, d__2 = temp * vmultc[k] + ratio * vmultd[k];
	vmultc[k] = (real) max(d__1,d__2);
    }
    if (mcon == *m) {
	resmax = resold + ratio * (resmax - resold);
    }

/*     If the full step is not acceptable then begin another iteration. */
/*     Otherwise switch to stage two or end the calculation. */

    if (icon > 0) {
	goto L70;
    }
    if (step == stpful) {
	goto L500;
    }
L480:
    mcon = *m + 1;
    icon = mcon;
    iact[mcon] = mcon;
    vmultc[mcon] = 0.f;
    goto L60;

/*     We employ any freedom that may be available to reduce the objective */
/*     function before returning a DX whose length is less than RHO. */

L490:
    if (mcon == *m) {
	goto L480;
    }
    *ifull = 0;
L500:
    return 0;
} /* trstlp_ */


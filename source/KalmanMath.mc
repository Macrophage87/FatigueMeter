using Toybox.Lang;

//! Pure linear-algebra for the 4-state linear Kalman filter (white paper §4).
//! Matrices are row-major Array-of-Arrays (4x4); vectors are Array[4]. Everything
//! is pure and finite-safe so it can be unit-tested off device and can never
//! throw into compute().
module KalmanMath {

    function zeros4x4() {
        return [ [0.0,0.0,0.0,0.0], [0.0,0.0,0.0,0.0],
                 [0.0,0.0,0.0,0.0], [0.0,0.0,0.0,0.0] ];
    }

    function matMul(a, b) {
        var out = zeros4x4();
        for (var i = 0; i < 4; i++) {
            for (var j = 0; j < 4; j++) {
                var s = 0.0;
                for (var k = 0; k < 4; k++) { s += a[i][k] * b[k][j]; }
                out[i][j] = s;
            }
        }
        return out;
    }

    function transpose(a) {
        var out = zeros4x4();
        for (var i = 0; i < 4; i++) {
            for (var j = 0; j < 4; j++) { out[i][j] = a[j][i]; }
        }
        return out;
    }

    //! Predict: x' = A·x + u ; P' = A·P·Aᵀ + Q(diag).
    //! u already folds in the known input terms Bu (all nonlinearities of P).
    function predict(x, P, A, u, qDiag) {
        // x' = A x + u
        var xNew = [0.0,0.0,0.0,0.0];
        for (var i = 0; i < 4; i++) {
            var s = u[i];
            for (var j = 0; j < 4; j++) { s += A[i][j] * x[j]; }
            xNew[i] = s;
        }
        // P' = A P Aᵀ + Q
        var AP = matMul(A, P);
        var Pnew = matMul(AP, transpose(A));
        for (var i = 0; i < 4; i++) { Pnew[i][i] += qDiag[i]; }
        symmetrize(Pnew);
        return [xNew, Pnew];
    }

    //! Scalar measurement update with row vector H (Array[4]), scalar z, scalar R.
    //! Handles a single channel; skip the call to leave that channel un-updated
    //! (native missing-observation handling — white paper §8.4).
    function scalarUpdate(x, P, H, z, R) {
        // PHt[i] = Σ_j P[i][j]·H[j]
        var PHt = [0.0,0.0,0.0,0.0];
        for (var i = 0; i < 4; i++) {
            var s = 0.0;
            for (var j = 0; j < 4; j++) { s += P[i][j] * H[j]; }
            PHt[i] = s;
        }
        // S = H·PHt + R
        var S = R;
        for (var i = 0; i < 4; i++) { S += H[i] * PHt[i]; }
        if (S < 1.0e-9) { return [x, P]; }   // degenerate; skip safely
        // Hx
        var Hx = 0.0;
        for (var i = 0; i < 4; i++) { Hx += H[i] * x[i]; }
        var innov = z - Hx;
        // K = PHt / S ; x += K·innov ; P -= K·(PHt)ᵀ
        var xNew = [0.0,0.0,0.0,0.0];
        for (var i = 0; i < 4; i++) { xNew[i] = x[i] + (PHt[i] / S) * innov; }
        var Pnew = KalmanMath.copy4x4(P);
        for (var i = 0; i < 4; i++) {
            var ki = PHt[i] / S;
            for (var j = 0; j < 4; j++) {
                Pnew[i][j] = P[i][j] - ki * PHt[j];
            }
        }
        symmetrize(Pnew);
        return [xNew, Pnew];
    }

    function copy4x4(a) {
        var out = zeros4x4();
        for (var i = 0; i < 4; i++) {
            for (var j = 0; j < 4; j++) { out[i][j] = a[i][j]; }
        }
        return out;
    }

    //! Force symmetry and a small positive diagonal floor -> keeps P conditioned.
    function symmetrize(P) {
        for (var i = 0; i < 4; i++) {
            for (var j = i + 1; j < 4; j++) {
                var m = (P[i][j] + P[j][i]) / 2.0;
                P[i][j] = m; P[j][i] = m;
            }
            if (P[i][i] < 1.0e-6) { P[i][i] = 1.0e-6; }
        }
        return P;
    }
}

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

    //! Row-vector × matrix: r[j] = Σ_i v[i]·A[i][j].
    function vecMatMul(v, A) {
        var out = [0.0, 0.0, 0.0, 0.0];
        for (var j = 0; j < 4; j++) {
            var s = 0.0;
            for (var i = 0; i < 4; i++) { s += v[i] * A[i][j]; }
            out[j] = s;
        }
        return out;
    }

    //! §4.3a mandatory observability/conditioning check. Builds the discrete
    //! observability matrix O = [H; H·A; H·A²; H·A³] (stacked for every
    //! measurement row H) and returns the non-degeneracy of the F state:
    //!   { :observable, :detGram, :fEnergy }
    //! where detGram = det(OᵀO) (>0 ⇔ full rank ⇔ non-degenerate observability
    //! Gramian) and fEnergy = (OᵀO)[F][F] (how strongly F projects onto the
    //! observation history). Proves NUMERICAL recoverability under the assumed
    //! model only — NOT physiological identifiability (that needs the pilot §10).
    function observabilityCheck(A, Hrows) {
        var O = [];
        for (var h = 0; h < Hrows.size(); h++) {
            var r = [Hrows[h][0], Hrows[h][1], Hrows[h][2], Hrows[h][3]];
            O.add(r);
            for (var pw = 0; pw < 3; pw++) {
                r = vecMatMul(r, A);
                O.add(r);
            }
        }
        // Gram = OᵀO (4x4)
        var G = zeros4x4();
        for (var i = 0; i < 4; i++) {
            for (var j = 0; j < 4; j++) {
                var s = 0.0;
                for (var k = 0; k < O.size(); k++) { s += O[k][i] * O[k][j]; }
                G[i][j] = s;
            }
        }
        var det = det4(G);
        var fEnergy = G[3][3];   // F is state index 3
        return { :observable => (det > 1.0e-6) && (fEnergy > 1.0e-6),
                 :detGram => det, :fEnergy => fEnergy };
    }

    //! Determinant of a 4x4 (cofactor expansion along the first row).
    function det4(m) {
        var det = 0.0;
        for (var c = 0; c < 4; c++) {
            var minor = minor3(m, 0, c);
            var sign = (c % 2 == 0) ? 1.0 : -1.0;
            det += sign * m[0][c] * det3(minor);
        }
        return det;
    }
    hidden function minor3(m, skipRow, skipCol) {
        var out = [];
        for (var i = 0; i < 4; i++) {
            if (i == skipRow) { continue; }
            var row = [];
            for (var j = 0; j < 4; j++) {
                if (j == skipCol) { continue; }
                row.add(m[i][j]);
            }
            out.add(row);
        }
        return out;
    }
    hidden function det3(m) {
        return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
             - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
             + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
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

using Base.LinAlg: Givens, Rotation, givensAlgorithm
import Base: @propagate_inbounds

"""
Computes the eigenvalues of the matrix A. Assumes that A is in Schur form.
"""
function eigvalues(A::AbstractMatrix{T}; tol = eps(real(T))) where {T}
    n = size(A, 1)
    λs = Vector{complex(T)}(n)
    i = 1

    while i < n
        if abs(A[i + 1, i]) < tol*(abs(A[i + 1, i + 1]) + abs( A[i, i]))
            λs[i] =  A[i, i]
            i += 1
        else
            d =  A[i, i]*A[i + 1, i + 1] - A[i, i + 1]*A[i + 1, i]
            x = 0.5*(A[i, i] + A[i + 1, i + 1])
            y = sqrt(complex(x*x - d))
            λs[i] = x + y
            λs[i + 1] = x - y
            i += 2
        end
    end

    if i == n 
        λs[i] = A[n, n] 
    end

    return λs
end

@propagate_inbounds is_offdiagonal_small(H, i, tol) = abs(H[i+1,i]) < tol*(abs(H[i,i]) + abs(H[i+1,i+1]))

local_schurfact!(A, Q) = local_schurfact!(A, Q, 1, size(A, 1))

function local_schurfact!(H::AbstractMatrix{T}, Q::AbstractMatrix{T}, start, stop; tol = eps(real(T)), debug = false, maxiter = 100*size(H, 1)) where {T<:Real}
    to = stop

    # iteration count
    iter = 0

    @inbounds while true
        iter += 1

        # Don't like that this throws :|
        # iter > maxiter && throw(ArgumentError("iteration limit $maxiter reached"))
        iter > maxiter && return false

        # Indexing
        # `to` points to the column where the off-diagonal value was last zero.
        # while `from` points to the smallest index such that there is no small off-diagonal
        # value in columns from:end-1. Sometimes `from` is just 1. Cartoon of a split 
        # with from != 1:
        # 
        #  + + | | | | + +
        #  + + | | | | + +
        #    o X X X X = =
        #      X X X X = =
        #      . X X X = =
        #      .   X X = =
        #      .     o + +
        #      .     . + +
        #      ^     ^
        #   from   to
        # The X's form the unreduced Hessenberg matrix we are applying QR iterations to,
        # the | and = values get updated by Given's rotations, while the + values remain
        # untouched! The o's are zeros -- or numerically considered zeros.

        # We keep `from` one column past the zero off-diagonal value, so we check whether
        # the `from - 1` column has a small off-diagonal value.
        from = to
        while from > start && !is_offdiagonal_small(H, from - 1, tol)
            from -= 1
        end

        if from == to
            # This just means H[to, to-1] == 0, so one eigenvalue converged at the end
            to -= 1
            debug && @printf("Bottom deflation! Block size is one. New to is %6d\n", to)
        else
            # Now we are sure we can work with a 2x2 block H[to-1:to,to-1:to]
            # We check if this block has a conjugate eigenpair, which might mean we have
            # converged w.r.t. this block if from + 1 == to. 
            # Otherwise, if from + 1 < to, we do either a single or double shift, based on
            # whether the H[to-1:to,to-1:to] part has real eigenvalues or a conjugate pair.

            H₁₁, H₁₂ = H[to-1,to-1], H[to-1,to]
            H₂₁, H₂₂ = H[to  ,to-1], H[to  ,to]

            # Matrix determinant and trace
            d = H₁₁ * H₂₂ - H₂₁ * H₁₂
            t = H₁₁ + H₂₂

            debug && @printf("block start is: %6d, block end is: %6d, d: %10.3e, t: %10.3e\n", from, to, d, t)

            # Quadratic eqn discriminant
            discriminant = t * t - 4d

            if discriminant > zero(T)
                # Real eigenvalues.
                # Note that if from + 1 == to in this case, then just one additional
                # iteration is necessary, since the Wilkinson shift will do an exact shift.

                # Determine the Wilkinson shift -- the closest eigenvalue of the 2x2 block
                # near H[to,to]
                sqr = sqrt(discriminant)
                λ₁ = (t + sqr) / 2
                λ₂ = (t - sqr) / 2
                λ = abs(H₂₂ - λ₁) < abs(H₂₂ - λ₂) ? λ₁ : λ₂
                # Run a bulge chase
                singleShiftQR!(H, Q, λ, from, to)
                # print("Single shift")
            else
                # Conjugate pair
                if from + 1 == to
                    # A conjugate pair has converged apparently!
                    to -= 2
                    debug && @printf("Bottom deflation! Block size is two. New to is %6d\n", to)
                else
                    # Otherwise we do a double shift!
                    sqr = sqrt(complex(discriminant))
                    λ = (t + sqr) / 2
                    double_shift_schur!(H, from, to, λ, Q)
                    print("Double shift")
                end
            end
        end

        debug && @show to

        # Converged!
        to ≤ start && break
    end

    return true
end

function local_schurfact!(H::AbstractMatrix{T}, Q::AbstractMatrix{T}, start, stop; tol = eps(real(T)), debug = false, maxiter = 100*size(H, 1)) where {T}
    to = stop

    # iteration count
    iter = 0

    @inbounds while true
        iter += 1

        # Don't like that this throws :|
        # iter > maxiter && throw(ArgumentError("iteration limit $maxiter reached"))
        iter > maxiter && return false

        # Indexing
        # `to` points to the column where the off-diagonal value was last zero.
        # while `from` points to the smallest index such that there is no small off-diagonal
        # value in columns from:end-1. Sometimes `from` is just 1. Cartoon of a split 
        # with from != 1:
        # 
        #  + + | | | | + +
        #  + + | | | | + +
        #    o X X X X = =
        #      X X X X = =
        #      . X X X = =
        #      .   X X = =
        #      .     o + +
        #      .     . + +
        #      ^     ^
        #   from   to
        # The X's form the unreduced Hessenberg matrix we are applying QR iterations to,
        # the | and = values get updated by Given's rotations, while the + values remain
        # untouched! The o's are zeros -- or numerically considered zeros.

        # We keep `from` one column past the zero off-diagonal value, so we check whether
        # the `from - 1` column has a small off-diagonal value.
        from = to
        while from > start && !is_offdiagonal_small(H, from - 1, tol)
            from -= 1
        end

        if from == to
            # This just means H[to, to-1] == 0, so one eigenvalue converged at the end
            to -= 1
            debug && @printf("Bottom deflation! Block size is one. New to is %6d\n", to)
        else
            # Now we are sure we can work with a 2x2 block H[to-1:to,to-1:to]
            # We check if this block has a conjugate eigenpair, which might mean we have
            # converged w.r.t. this block if from + 1 == to. 
            # Otherwise, if from + 1 < to, we do either a single or double shift, based on
            # whether the H[to-1:to,to-1:to] part has real eigenvalues or a conjugate pair.

            H₁₁, H₁₂ = H[to-1,to-1], H[to-1,to]
            H₂₁, H₂₂ = H[to  ,to-1], H[to  ,to]

            # Matrix determinant and trace
            d = H₁₁ * H₂₂ - H₂₁ * H₁₂
            t = H₁₁ + H₂₂

            debug && @printf("block start is: %6d, block end is: %6d, d: %10.3e, t: %10.3e\n", from, to, d, t)

            # Quadratic eqn discriminant
            discriminant = t * t - 4d

            # Note that if from + 1 == to in this case, then just one additional
            # iteration is necessary, since the Wilkinson shift will do an exact shift.

            # Determine the Wilkinson shift -- the closest eigenvalue of the 2x2 block
            # near H[to,to]
            sqr = sqrt(discriminant)
            λ₁ = (t + sqr) / 2
            λ₂ = (t - sqr) / 2
            λ = abs(H₂₂ - λ₁) < abs(H₂₂ - λ₂) ? λ₁ : λ₂
            # Run a bulge chase
            singleShiftQR!(H, Q, λ, from, to)
            # print("Single shift")
        end

        debug && @show to

        # Converged!
        to ≤ start && break
    end

    return true
end

function singleShiftQR!(HH::StridedMatrix, Q::AbstractMatrix, shift::Number, istart::Integer, iend::Integer)
    m = size(HH, 1)
    H11 = HH[istart, istart]
    H21 = HH[istart + 1, istart]
    if m > istart + 1
        Htmp = HH[istart + 2, istart]
        HH[istart + 2, istart] = 0
    end
    c, s = givensAlgorithm(H11 - shift, H21)
    G = Givens(c, s, istart)
    mul!(G, HH)
    mul!(HH, G)
    mul!(Q, G)
    for i = istart:iend - 2
        c, s = givensAlgorithm(HH[i + 1, i], HH[i + 2, i])
        G = Givens(c, s, i + 1)
        mul!(G, HH)
        HH[i + 2, i] = Htmp
        if i < iend - 2
            Htmp = HH[i + 3, i + 1]
            HH[i + 3, i + 1] = 0
        end
        mul!(HH, G)
        mul!(Q, G)
    end
    return HH
end

function doubleShiftQR!(HH::StridedMatrix, Q::AbstractMatrix, shiftTrace::Number, shiftDeterminant::Number, istart::Integer, iend::Integer)
    m = size(HH, 2)
    H11 = HH[istart, istart]
    H21 = HH[istart + 1, istart]
    Htmp11 = HH[istart + 2, istart]
    HH[istart + 2, istart] = 0
    if istart + 3 <= m
        Htmp21 = HH[istart + 3, istart]
        HH[istart + 3, istart] = 0
        Htmp22 = HH[istart + 3, istart + 1]
        HH[istart + 3, istart + 1] = 0
    else
        # values doen't matter in this case but variables should be initialized
        Htmp21 = Htmp22 = Htmp11
    end
    c1, s1, nrm = givensAlgorithm(H21*(H11 + HH[istart + 1, istart + 1] - shiftTrace), H21*HH[istart + 2, istart + 1])
    G1 = Givens(c1, s1, istart + 1)
    c2, s2, _ = givensAlgorithm(H11*H11 + HH[istart, istart + 1]*H21 - shiftTrace*H11 + shiftDeterminant, nrm)
    G2 = Givens(c2, s2, istart)

    vHH = view(HH, :, istart:m)
    mul!(G1, vHH)
    mul!(G2, vHH)
    vHH = view(HH, 1:min(istart + 3, m), :)
    mul!(vHH, G1)
    mul!(vHH, G2)
    mul!(Q, G1)
    mul!(Q, G2)

    for i = istart:iend - 2
        for j = 2:1
            if i + j + 1 > iend break end
            # G, _ = givens(H.H,i+1,i+j+1,i)
            c, s, _ = givensAlgorithm(HH[i + j, i], HH[i + j + 1, i])
            G = Givens(c, s, i + j)
            mul!(G, view(HH, :, i:m))

            # Not sure what this was for
            # HH[i + j + 1, i] = Htmp11
            # Htmp11 = Htmp21
            
            # Commented out from the start 
            # if i + j + 2 <= iend
                # Htmp21 = HH[i + j + 2, i + 1]
                # HH[i + j + 2, i + 1] = 0
            # end
            
            if i + 4 <= iend
                Htmp22 = HH[i + 4, i + j]
                HH[i + 4, i + j] = 0
            end
            mul!(view(HH, 1:min(i + j + 2, iend), :), G)
            mul!(Q, G)
        end
    end
    return HH
end

function double_shift_schur!(H::AbstractMatrix{Tv}, min, max, μ::Complex, Q::AbstractMatrix) where {Tv<:Real}
    # Compute the three nonzero entries of (H - μ₂)(H - μ₁)e₁.
    p₁ = abs2(μ) - 2 * real(μ) * H[min,min] + H[min,min] * H[min,min] + H[min,min+1] * H[min+1,min]
    p₂ = -2.0 * real(μ) * H[min+1,min] + H[min+1,min] * H[min,min] + H[min+1,min+1] * H[min+1,min]
    p₃ = H[min+2,min+1] * H[min+1,min]

    # Map that column to a mulitiple of e₁ via three Given's rotations
    c₁, s₁, nrm = givensAlgorithm(p₂, p₃)
    c₂, s₂,     = givensAlgorithm(p₁, nrm)
    G₁ = Givens(c₁, s₁, min+1)
    G₂ = Givens(c₂, s₂, min)

    # Apply the Given's rotations
    mul!(G₁, H)
    mul!(G₂, H)
    mul!(H, G₁)
    mul!(H, G₂)

    # Update Q
    mul!(Q, G₁)
    mul!(Q, G₂)

    # Bulge chasing. First step of the for-loop below looks like:
    #   min           max
    #     ↓           ↓
    #     x x x x x x x     x x x x x x x     x + + + x x x
    # i → x x x x x x x     + + + + + + +     x + + + x x x 
    #     x x x x x x x     o + + + + + +       + + + x x x
    #     x x x x x x x  ⇒  o + + + + + +  ⇒   + + + x x x
    #       |   x x x x           x x x x       + + + x x x
    #       |     x x x             x x x             x x x
    #       |       x x               x x               x x
    #       ↑
    #       i
    #
    # Last iterations looks like:
    #   min           max
    #     ↓           ↓
    #     x x x x x x x     x x x x x x x     x x x x + + +
    #     x x x x x x x     x x x x x x x     x x x x + + +
    #       x x x x x x       x x x x x x       x x x + + +
    #         x x x x x  ⇒    x x x x x x  ⇒     x x + + +
    # i → ----- x x x x           + + + +           x + + +
    #           x x x x           o + + +             + + +
    #           x x x x           o + + +             + + +
    #             ↑
    #             i

    for i = min + 1 : max - 2
        c₁, s₁, nrm = givensAlgorithm(H[i+1,i-1], H[i+2,i-1])
        c₂, s₂,     = givensAlgorithm(H[i,i-1], nrm)
        G₁ = Givens(c₁, s₁, i+1)
        G₂ = Givens(c₂, s₂, i)

        # Restore to Hessenberg
        mul!(G₁, H)
        mul!(G₂, H)

        # Introduce zeros below Hessenberg part
        H[i+1,i-1] = zero(Tv)
        H[i+2,i-1] = zero(Tv)

        # Create a new bulge
        mul!(H, G₁)
        mul!(H, G₂)

        # Update Q
        mul!(Q, G₁)
        mul!(Q, G₂)
    end

    # Last bulge is just one Given's rotation
    #     min           max
    #       ↓           ↓
    # min → x x x x x x x    x x x x x x x    x x x x x + +  
    #       x x x x x x x    x x x x x x x    x x x x x + +  
    #         x x x x x x      x x x x x x      x x x x + +  
    #           x x x x x  ⇒     x x x x x  ⇒    x x x + +  
    #             x x x x          x x x x          x x + +  
    #               x x x            + + +            x + +  
    # max → ------- x x x            o + +              + +


    c, s, = givensAlgorithm(H[max-1,max-2], H[max,max-2])
    G = Givens(c, s, max-1)
    mul!(G, H)
    H[max,max-2] = zero(Tv)
    mul!(H, G)
    mul!(Q, G)

    H
end
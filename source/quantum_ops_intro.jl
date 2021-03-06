# # QuantumOps Implementation
# ## Overview
#
#  The main design idea was to provide a straightforward implementation of operators
#  that is sufficiently general to represent both Pauli and Fermionic operators (and possibly others);
#  The implementation should be fairly efficient, while not requiring too
#  much code specialized to the concrete types. The operators should have similar
#  functionality to `SparsePauliOp` in qiskit.quantum_info and `FermionicOp` in qiskit_nature.
#
# `QuantumOps` is built mainly around three levels of operator types
# * `AbstractOp` -- representing single-particle Fermionic or Pauli operators
# * `OpTerm` -- a parametric type implementing a string of operators as an `AbstractVector{<:AbstractOp}`
#   and a coefficient. `OpTerm` represents a multi-particle/mode term. The string type may be a dense
#  `Vector` or a `SparseVector` (with identities not stored). The coefficient may be numeric or symbolic.
# * `OpSum` -- a parametric type representing a sum of `OpTerm`s. `OpSum` is implemented as a `Vector`
#   of `OpTerms` that are maintained in a canonical order.
#
# Some features are
# * `QuantumOps` tries to make the structures and methods efficient, but there is little done to optimize
#    them. Still, `QuantumOps` is often one to three orders of magnitude faster
#    than Qiskit. [Note: This was before the series of big improvements to `SparsePauliOp`.]
# * `QuantumOps` works together `ElectronicStructure.jl` to represent electonic Hamiltonians.
# *  The Jordan-Wigner transform is implemented as an example.
# *  A package `qisit_alt` provides a demonstration of Python wrappers allowing Qiskit classes as input and output.
#
# First, import some identifiers for types
import QuantumOps ## Import the identifier `QuantumOps` for using fully qualified identifiers
using QuantumOps: AbstractOp, AbstractFermiOp, FermiOp, AbstractPauli, Pauli, PauliI
#
# ## Simple operators -- `AbstractOp`
# Types for Fermionic and Pauli operators on a single mode or qubit have `AbstractOp` as an ancestor.
# We have
FermiOp <: AbstractFermiOp <: AbstractOp
# and
Pauli <: AbstractPauli <: AbstractOp
# There is an alternative encoding for Pauli operators
PauliI <: AbstractPauli <: AbstractOp
# `PauliI` may be more efficient in some circumstances.
# None (almost) of `QuantumOps` is written explicitly against a subtype of `AbstractPauli`,
# so `Pauli` and `PauliI` may be used interchangeably. Eventually, probably only one of the two will be retained.
# For brevity, we won't consider `PauliI` in this document.
#
# All subtypes of `AbstractPauliOp` may instantiated by an integer index like this
(Pauli(0), Pauli(1), Pauli(2), Pauli(3))

# Recall that this expression may also be written using broadcasting like this
Pauli.((0, 1, 2, 3))

# Seven (or maybe six) Fermi operators are supported
FermiOp.((0:6...,))

# The symbols mean the following

# (I = identity, N = number, E = complement of number (empty), + = raising, - = lowering, 0 = zero, Z = N - E)

# For convenience, you can use variables that name the operators. For example
using QuantumOps.Paulis: I, X, Y, Z
(I, X, Y, Z)

# The details of `Pauli` and `FermiOp` are hidden. For example, even `OpTerm` and supporting code
# knows nothing about how they are represented. But here is a look indside
dump(QuantumOps.Paulis.X)
#-
dump(QuantumOps.PaulisI.X)
#-
dump(QuantumOps.FermiOps.NumberOp)

# ## Multi-qubit/mode operators -- `OpTerm`
# Operators on multiple qubits or degrees of freedom, together with a coefficient, are represented by `OpTerm`.
using QuantumOps: OpTerm, PauliTerm, FermiTerm

# `PauliTerm` and `FermiTerm` are aliases in a strong sense.
OpTerm{Pauli}
#-
OpTerm{FermiOp}
#-
PauliTerm === OpTerm{Pauli} # `===` means that within the semantics of Julia they cannot be distinguished.

# One way to instantiate an `OpTerm` is from a string, like this
OpTerm{Pauli}("IXIYIZ", 1.0 + 1.0im)
# Or, for Fermionic operators
OpTerm{FermiOp}("++I--NE", 1.0)
# Alternatively, we can use the aliases for convenience
PauliTerm("IXIYIZ", 1.0 + 1.0im)
FermiTerm("++I--NE")
# To be clear, note that
FermiTerm("+-INE")
# means ``a_0^\dagger a_1 a^\dagger_3 a_3 a_4 a^\dagger_4``.
#
md"""
`OpTerm` is a [parametric type with three parameters](https://github.ibm.com/John-Lapeyre/QuantumOps.jl/blob/045dd86a93aff579973dbcc42ce4b3fad0d1a229/src/op_term.jl#L10-L13).
```julia
struct OpTerm{W<:AbstractOp, T<:AbstractVector{W}, CoeffT} <: AbstractTerm{W, CoeffT}
   ops::T
   coeff::CoeffT
end
```
The first, `W` is the operator type.
The second, `T` specifies the type of storage for the string of operators.
The third, `CoeffT` is the type of the coefficient.
The aliases `PauliTerm` and `FermiTerm` each have a concrete first
paramter `Pauli` and `FermiOp` respectively. The remaining two parameters are free.
By default, constructors make the second parameter a dense `Vector`. For the concrete operator types that we
have implemented, `Pauli`, and `FermiOp`, it will be an effcient, packed array of bitstype objects.
The type of the coefficient is not constrained, but should support multiplication
and addition. It may be, for example, `ComplexF64`, or a symbolic type.
"""

# ## Sparse operators
# Terms with sparse storage of operator strings are supported by using a sparse array type with `OpTerm`.
# We use a generalized (at no runtime cost) version of the standard Julia `SparseVector` that allows one to
# specify that the neutral element of `AbstractOp` in the sparse vector should be the identity rather than zero.
# For example
using QuantumOps: sparse_op, dense_op
sparse_op(OpTerm{Pauli}("IIIIIXIYIZ", 1.0 + 1.0im))
# You can convert back like this
dense_op(sparse_op(OpTerm{Pauli}("IIIIIXIYIZ", 1.0 + 1.0im)))

## Sums of multi-qubit/mode operators -- `OpSum`

# ## Arithemetic on operators

# Multiplication is defined between simple operators, but types are not promoted to
# types capable of representing phase, so the phase is not tracked.
# For example
X * Y

import QuantumOps.FermiOps as FOps
FOps.NumberOp * FOps.NumberOp
#-
FOps.Raise * FOps.Lower

# Multiplying terms does correctly preserve the phase.
t1 = PauliTerm("X")
#-
t2 = PauliTerm("Y")
#-
t1 * t2

#-

t1 = PauliTerm("XIYIZ")
#-
t2 = PauliTerm("YXIZZ")
#-
t1 * t2
# Sparse terms also support `*`
sparse_op(t1) * sparse_op(t2)
# Multiplication between sparse and dense terms is currently not supported.

# ## `OpTerm` features

# You can create a generator of the ``n``-qubit Pauli basis operators like this
collect(QuantumOps.pauli_basis(2))  # collect the generator in an `Array`

# ## `OpSum` -- sums of multi-particle terms

#

#-

nothing;

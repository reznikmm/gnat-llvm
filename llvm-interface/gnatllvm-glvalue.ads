------------------------------------------------------------------------------
--                             G N A T - L L V M                            --
--                                                                          --
--                     Copyright (C) 2013-2018, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Stand; use Stand;
with Uintp; use Uintp;

with LLVM.Core;   use LLVM.Core;

with Interfaces.C;             use Interfaces.C;
with Interfaces.C.Extensions; use Interfaces.C.Extensions;

with GNATLLVM.Wrapper;     use GNATLLVM.Wrapper;

package GNATLLVM.GLValue is

   --  It's not sufficient to just pass around an LLVM Value_T when
   --  generating code because there's a lot of information lost about
   --  the value and where it came from.  We contruct a record of type
   --  GL_Value, which contains the LLVM Value_T (which, in turn
   --  contains it's LLVM Type_T), a GNAT type to which it's related,
   --  and a field indicating the relationship between the value and
   --  the type.  For example, the value may contain bits of the type
   --  or the value may be the address of the bits of the type.

   type GL_Value_Relationship is
     (Data,
      --  Value is actual bits of Typ.  This can never be set for
      --  subprogram types or for types of variable size.  It can be set
      --  for non-first-class types in the LLVM sense as long as LLVM can
      --  represent a value of that object.  If Typ is an access type, this
      --  is requivalent to a relationship of Reference to the
      --  Designated_Type of Typ.

      Reference,
      --  Value contains the address of an object of Typ.  This is always
      --  the case for types of variable size or for names corresponding to
      --  globals because those names represent the address of the global,
      --  either for data or functions.

      Double_Reference,
      --  Value contains the address of memory that contains the address of
      --  an object of Typ.  This occurs for globals where either an
      --  'Address attribute was specifed or where an object of dynamic
      --  size was allocated because in both of those cases the global name
      --  is a pointer to a location containing the address of the object.

      Fat_Pointer,
      --  Value contains a "fat pointer", an object containing information
      --  about both the data and bounds of an unconstrained array object
      --  of Typ.

      Bounds,
      --  Value contains data representing the bounds of an object of Typ,
      --  which must be an unconstrained array type.

      Reference_To_Bounds,
      --  Value contains an address that points to the bounds of an object
      --  of Typ, which must be an unconstrained type.

      Array_Data,
      --  Value contains the address of the first byte of memory that
      --  contains the value of the array.  For constrained arrays, this
      --  is the same as Reference.

      Reference_To_Subprogram,
      --  Value contains the address of a subprogram which is a procedure
      --  if Typ is an E_Void or which is a function returning type Typ
      --  if Typ is not a Void.  If Typ is a subprogram type, then
      --  Reference should be used instead and if Typ is an access
      --  to subprogram type, then Data is the appropriate relationship.

      Invalid);
      --  This is invalid relationship, which will result from, e.g.,
      --  doing a dereference operation on something that isn't a reference.

   --  We define some properties on each relationship type so we can
   --  do some reasoning on them.  This record and array are used to express
   --  those properties.

   type Relationship_Property is record
     Reference : Boolean;
     --  True if this is a reference to something

     Deref     : GL_Value_Relationship;
     --  The relationship corresponding to a dereference (Load) from a
     --  GL_Valule that has this relationship.
   end record;

   type Relationship_Array is
     array (GL_Value_Relationship) of Relationship_Property;

   Relation_Props : constant Relationship_Array :=
     (Data                     => (Reference => False, Deref => Invalid),
      Reference                => (Reference => True,  Deref => Data),
      Double_Reference         => (Reference => True,  Deref => Reference),
      Fat_Pointer              => (Reference => True,  Deref => Invalid),
      Bounds                   => (Reference => False, Deref => Invalid),
      Reference_To_Bounds      => (Reference => True,  Deref => Bounds),
      Array_Data               => (Reference => True,  Deref => Invalid),
      Reference_To_Subprogram  => (Reference => True,  Deref => Invalid),
      Invalid                  => (Reference => False, Deref => Invalid));

   type GL_Value_Base is record
      Value                : Value_T;
      --  The LLVM value that was generated

      Typ                  : Entity_Id;
      --  The GNAT type of this value

      Relationship         : GL_Value_Relationship;
      --  The relationship between Value and Typ.
   end record;
   --  We want to put a Predicate on this, but can't, so we need to make
   --  a subtype for that purpose.

   function GL_Value_Is_Valid (V : GL_Value_Base) return Boolean;
   --  Return whether V is a valid GL_Value or not

   subtype GL_Value is GL_Value_Base
     with Predicate => GL_Value_Is_Valid (GL_Value);
   --  Subtype used by everybody except validation function

   type GL_Value_Array is array (Nat range <>) of GL_Value;

   No_GL_Value : constant GL_Value := (No_Value_T, Empty, Data);
   function No      (V : GL_Value) return Boolean      is (V =  No_GL_Value);
   function Present (V : GL_Value) return Boolean      is (V /= No_GL_Value);

   --  Define basic accessors for components of GL_Value

   function LLVM_Value (V : GL_Value) return Value_T is
     (V.Value)
     with Pre => Present (V), Post => Present (LLVM_Value'Result);
   --  Return the LLVM value in the GL_Value

   function Related_Type (V : GL_Value) return Entity_Id is
     (V.Typ)
     with Pre => Present (V), Post => Is_Type_Or_Void (Related_Type'Result);
   --  Return the type to which V is related, irrespective of the
   --  relationship.

   function Relationship (V : GL_Value) return GL_Value_Relationship is
     (V.Relationship)
     with Pre => Present (V);

   --  Now some predicates derived from the above

   function Is_Reference (V : GL_Value) return Boolean is
     (Relation_Props (Relationship (V)).Reference)
     with Pre => Present (V);

   function Is_Raw_Array (V : GL_Value) return Boolean is
     (Relationship (V) = Array_Data)
     with Pre => Present (V);

   function Is_Double_Reference (V : GL_Value) return Boolean is
     (Relationship (V) = Double_Reference)
     with Pre => Present (V);

   function Is_Subprogram_Reference (V : GL_Value) return Boolean is
     (Relationship (V) = Reference_To_Subprogram)
     with Pre => Present (V);

   function Has_Known_Etype (V : GL_Value) return Boolean is
     (Relationship (V) = Data)
     with Pre => Present (V);
   --  True if we know what V's Etype is

   function Etype (V : GL_Value) return Entity_Id is
     (V.Typ)
     with Pre => Present (V) and then Has_Known_Etype (V),
          Post => Is_Type_Or_Void (Etype'Result);

   --  Now we have constructors for a GL_Value

   function G
     (V                    : Value_T;
      TE                   : Entity_Id;
      Relationship         : GL_Value_Relationship := Data) return GL_Value is
     ((V, TE, Relationship))
     with Pre => Present (V) and then Is_Type_Or_Void (TE);
   --  Raw constructor that allow full specification of all fields

   function G_From (V : Value_T; GV : GL_Value) return GL_Value is
     (G (V, GV.Typ, GV.Relationship))
     with Pre  => Present (V) and then Present (GV),
          Post => Present (G_From'Result);
   --  Constructor for most common operation cases where we aren't changing
   --  any typing information, so we just copy it from an existing value.

   function G_Is (V : GL_Value; TE : Entity_Id) return GL_Value is
     (G (LLVM_Value (V), TE))
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Present (G_Is'Result);
   --  Constructor for case where we want to show that V has a different type

   function G_Is (V : GL_Value; T : GL_Value) return GL_Value is
     (G (LLVM_Value (V), Etype (T)))
     with Pre  => Present (V) and then Present (T),
          Post => Present (G_Is'Result);

   function G_Is_Ref (V : GL_Value; TE : Entity_Id) return GL_Value is
     (G (LLVM_Value (V), TE, Reference))
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Is_Access_Type (G_Is_Ref'Result);
   --  Constructor for case where we want to show that V has a different type

   function G_Is_Ref (V : GL_Value; T : GL_Value) return GL_Value is
     (G (LLVM_Value (V), Etype (T), Reference))
     with Pre  => Present (V) and then Present (T),
          Post => Is_Access_Type (G_Is_Ref'Result);

   function G_Ref (V : Value_T; TE : Entity_Id) return GL_Value is
     (G (V, TE, Reference))
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Is_Access_Type (G_Ref'Result);
   --  Constructor for case where we've create a value that's a pointer to
   --  type TE.

   function G_Ref (V : GL_Value; TE : Entity_Id) return GL_Value is
     (G (LLVM_Value (V), TE, Reference))
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Is_Access_Type (G_Ref'Result);
   --  Likewise but when we already have a GL_Value

   function G_Double_Ref (V : GL_Value; TE : Entity_Id) return GL_Value is
     (G (LLVM_Value (V), TE, Double_Reference))
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Is_Double_Reference (G_Double_Ref'Result);
   --  Likewise but when we already have a GL_Value

   procedure Discard (V : GL_Value);
   --  Evaluate V and throw away the result

   --  Now define predicates on the GL_Value type to easily access
   --  properties of the LLVM value and the effective type.  These have the
   --  same names as those for types and Value_T's.  The first of these
   --  represent abstractions that will be used in later predicates.

   function Full_Etype (V : GL_Value) return Entity_Id is
     (Etype (V))
     with Pre => Present (V), Post => Is_Type_Or_Void (Full_Etype'Result);

   function Type_Of (V : GL_Value) return Type_T is
     (Type_Of (LLVM_Value (V)))
     with Pre => Present (V), Post => Present (Type_Of'Result);

   function Ekind (V : GL_Value) return Entity_Kind is
     ((if Is_Reference (V) then E_Access_Type else Ekind (Etype (V))))
     with Pre => Present (V);

   function Is_Access_Type (V : GL_Value) return Boolean is
     (Is_Reference (V) or else Is_Access_Type (Etype (V)))
     with Pre => Present (V);

   function Full_Designated_Type (V : GL_Value) return Entity_Id
     with Pre  => Is_Access_Type (V) and then not Is_Double_Reference (V)
                  and then not Is_Subprogram_Reference (V),
          Post => Is_Type_Or_Void (Full_Designated_Type'Result);

   function Implementation_Base_Type (V : GL_Value) return Entity_Id is
     (Implementation_Base_Type (Etype (V)))
     with Pre  => not Is_Reference (V),
            Post => Is_Type (Implementation_Base_Type'Result);

   function Is_Dynamic_Size (V : GL_Value) return Boolean
     with Pre => Present (V);

   function Is_Array_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Array_Type (Etype (V)))
     with Pre => Present (V);

   function Is_Access_Unconstrained (V : GL_Value) return Boolean is
     (Is_Access_Type (V) and then Ekind (V.Typ) /= E_Void
        and then not Is_Subprogram_Reference (V)
        and then Is_Array_Type (Full_Designated_Type (V))
        and then not Is_Constrained (Full_Designated_Type (V))
        and then not Is_Raw_Array (V)
        and then Relationship (V) /= Reference_To_Subprogram)
     with Pre => Present (V);

   function Is_Constrained (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Constrained (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Record_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Record_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Composite_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Composite_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Elementary_Type (V : GL_Value) return Boolean is
     (Is_Reference (V) or else Is_Elementary_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Scalar_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Scalar_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Discrete_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Discrete_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Integer_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V)
        and then Is_Integer_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Fixed_Point_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Fixed_Point_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Floating_Point_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Floating_Point_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Unsigned_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Unsigned_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Discrete_Or_Fixed_Point_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V)
        and then Is_Discrete_Or_Fixed_Point_Type (Full_Etype (V)))
     with Pre => Present (V);

   function Is_Modular_Integer_Type (V : GL_Value) return Boolean is
     (not Is_Reference (V) and then Is_Modular_Integer_Type (Full_Etype (V)))
     with Pre => Present (V);

   function RM_Size (V : GL_Value) return Uint is
     (RM_Size (Full_Etype (V)))
     with Pre => not Is_Access_Type (V);

   function Esize (V : GL_Value) return Uint is
     (Esize (Full_Etype (V)))
     with Pre => not Is_Access_Type (V);

   function Component_Type (V : GL_Value) return Entity_Id is
     (Component_Type (Full_Etype (V)))
     with Pre => Is_Array_Type (V), Post => Present (Component_Type'Result);

   function Number_Dimensions (V : GL_Value) return Pos is
     (Number_Dimensions (Full_Etype (V)))
     with Pre => Is_Array_Type (V);

   function Make_Reference (V : GL_Value) return GL_Value is
     (G_Ref (LLVM_Value (V), Full_Designated_Type (V)))
     with Pre  => Is_Access_Type (V),
          Post => Is_Reference (Make_Reference'Result)
                  and then (Full_Designated_Type (Make_Reference'Result) =
                              Full_Designated_Type (V));
   --  Indicate that we want to consider G as a reference to its designated
   --  type.

   function Get_Undef (TE : Entity_Id) return GL_Value
     with Pre  => Is_Type (TE), Post => Present (Get_Undef'Result);

   function Get_Undef_Ref (TE : Entity_Id) return GL_Value
     with Pre  => Is_Type (TE), Post => Is_Reference (Get_Undef_Ref'Result);

   function Get_Undef_Ref (T : Type_T; TE : Entity_Id) return GL_Value is
     (G_Ref (Get_Undef (T), TE))
     with Pre  => Is_Type (TE), Post => Is_Reference (Get_Undef_Ref'Result);

   function Const_Null (TE : Entity_Id) return GL_Value
     with Pre  => Is_Type (TE), Post => Present (Const_Null'Result);

   function Const_Int (TE : Entity_Id; N : Uint) return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (TE) and then N /= No_Uint,
          Post => Present (Const_Int'Result);

   function Const_Int
     (TE          : Entity_Id;
      N           : unsigned_long_long;
      Sign_Extend : Boolean := False) return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Present (Const_Int'Result);

   function Const_Int
     (TE          : Entity_Id;
      N           : unsigned;
      Sign_Extend : Boolean := False) return GL_Value is
     (Const_Int (TE, unsigned_long_long (N), Sign_Extend))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Present (Const_Int'Result);

   function Const_Ones (TE : Entity_Id) return GL_Value is
     (Const_Int (TE, unsigned_long_long'Last, Sign_Extend => True))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Present (Const_Ones'Result);
   --  Return an LLVM value for the given type where all bits are set

   function Get_Undef (V : GL_Value) return GL_Value is
     (Get_Undef (Etype (V)))
     with  Pre  => Present (V), Post => Present (Get_Undef'Result);

   function Const_Null (V : GL_Value) return GL_Value is
     (Const_Null (Etype (V)))
     with Pre  => Present (V), Post => Present (Const_Null'Result);

   function Const_Null_Ref (TE : Entity_Id) return GL_Value
     with Pre  => Is_Type (TE), Post => Is_Reference (Const_Null_Ref'Result);

   function Const_Int (V : GL_Value; N : Uint) return GL_Value is
     (Const_Int (Etype (V), N))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V) and then N /= No_Uint,
          Post => Present (Const_Int'Result);

   function Const_Int
     (V           : GL_Value;
      N           : unsigned_long_long;
      Sign_Extend : Boolean := False) return GL_Value
   is
     (Const_Int (Etype (V), N, Sign_Extend))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V),
          Post => Present (Const_Int'Result);

   function Const_Int
     (V           : GL_Value;
      N           : unsigned;
      Sign_Extend : Boolean := False) return GL_Value
   is
     (Const_Int (Etype (V), unsigned_long_long (N), Sign_Extend))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V),
          Post => Present (Const_Int'Result);

   function Const_Ones (V : GL_Value) return GL_Value is
     (Const_Ones (Etype (V)))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V),
          Post => Present (Const_Ones'Result);
   --  Return an LLVM value for the given type where all bits are set

   function Const_Real (TE : Entity_Id; V : double) return GL_Value
     with Pre  => Is_Floating_Point_Type (TE),
          Post => Present (Const_Real'Result);

   function Size_Const_Int (N : Uint) return GL_Value is
     (Const_Int (Size_Type, N))
     with Pre  => N /= No_Uint, Post => Present (Size_Const_Int'Result);

   function Size_Const_Int
     (N : unsigned; Sign_Extend : Boolean := False) return GL_Value
   is
     (Const_Int (Size_Type, unsigned_long_long (N), Sign_Extend))
     with Post => Present (Size_Const_Int'Result);

   function Size_Const_Int
     (N : unsigned_long_long; Sign_Extend : Boolean := False) return GL_Value
   is
     (Const_Int (Size_Type, N, Sign_Extend))
     with Post => Present (Size_Const_Int'Result);

   function Size_Const_Null return GL_Value
   is
     (Size_Const_Int (unsigned_long_long (0)))
     with Post => Present (Size_Const_Null'Result);

   function Const_Int_32 (N : Uint) return GL_Value is
     (Const_Int (Int_32_Type, N))
     with Pre  => N /= No_Uint, Post => Present (Const_Int_32'Result);

   function Const_Int_32
     (N : unsigned_long_long; Sign_Extend : Boolean := False) return GL_Value
   is
     (Const_Int (Int_32_Type, N, Sign_Extend))
     with Post => Present (Const_Int_32'Result);

   function Const_Int_32
     (N : unsigned; Sign_Extend : Boolean := False) return GL_Value
   is
     (Const_Int (Int_32_Type, unsigned_long_long (N), Sign_Extend))
     with Post => Present (Const_Int_32'Result);

   function Const_Null_32 return GL_Value
   is
     (Const_Int_32 (unsigned_long_long (0)))
     with Post => Present (Const_Null_32'Result);

   function Const_Real (V : GL_Value; F : double) return GL_Value is
     (Const_Real (Etype (V), F))
     with Pre  => Is_Floating_Point_Type (V),
           Post => Present (Const_Real'Result);

   function Const_True return GL_Value is
     (Const_Int (Standard_Boolean, unsigned_long_long (1)));
   function Const_False return GL_Value is
     (Const_Int (Standard_Boolean, unsigned_long_long (0)));

   --  Define IR builder variants which take and/or return GL_Value

   function Alloca (TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Type (TE),
          Post => Is_Access_Type (Alloca'Result);

   function Array_Alloca
     (TE : Entity_Id; Num_Elts : GL_Value; Name : String := "") return GL_Value
     with Pre  => Is_Type (TE) and then Present (Num_Elts),
          Post => Is_Access_Type (Array_Alloca'Result);

   function Int_To_Ptr (V : GL_Value; TE : Entity_Id; Name : String := "")
     return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Access_Type (TE),
          Post => Is_Access_Type (Int_To_Ptr'Result);

   function Ptr_To_Int
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Access_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Is_Discrete_Or_Fixed_Point_Type (Ptr_To_Int'Result);

   function Bit_Cast
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Present (V) and then not Is_Access_Type (V)
                  and then Is_Type (TE) and then not Is_Access_Type (TE),
          Post => Present (Bit_Cast'Result);

   function Pointer_Cast
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Access_Type (V) and then Is_Access_Type (TE),
          Post => Is_Access_Type (Pointer_Cast'Result);

   function Ptr_To_Ref
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Access_Type (V) and then Is_Type (TE),
          Post => Is_Access_Type (Ptr_To_Ref'Result);

   function Ptr_To_Raw_Array
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Access_Type (V) and then Is_Type (TE),
          Post => Is_Access_Type (Ptr_To_Raw_Array'Result);

   function Trunc
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Is_Discrete_Or_Fixed_Point_Type (Trunc'Result);

   function S_Ext
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Is_Discrete_Or_Fixed_Point_Type (S_Ext'Result);

   function Z_Ext
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
          and then Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Is_Discrete_Or_Fixed_Point_Type (Z_Ext'Result);

   function FP_Trunc
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Floating_Point_Type (TE),
          Post => Is_Floating_Point_Type (FP_Trunc'Result);

   function FP_Ext
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Floating_Point_Type (TE),
          Post => Is_Floating_Point_Type (FP_Ext'Result);

   function FP_To_SI
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Is_Discrete_Or_Fixed_Point_Type (FP_To_SI'Result);

   function FP_To_UI
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (TE),
          Post => Is_Discrete_Or_Fixed_Point_Type (FP_To_UI'Result);

   function UI_To_FP
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Floating_Point_Type (TE),
          Post => Is_Floating_Point_Type (UI_To_FP'Result);

   function SI_To_FP
     (V : GL_Value; TE : Entity_Id; Name : String := "") return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Floating_Point_Type (TE),
          Post => Is_Floating_Point_Type (SI_To_FP'Result);

   function Int_To_Ptr
     (V, T : GL_Value; Name : String := "") return GL_Value is
     (Int_To_Ptr (V, Full_Etype (T), Name))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Access_Type (T),
          Post => Is_Access_Type (Int_To_Ptr'Result);

   function Ptr_To_Int
     (V, T : GL_Value; Name : String := "") return GL_Value is
     (Ptr_To_Int (V, Full_Etype (T), Name))
     with Pre  => Is_Access_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (T),
          Post => Is_Discrete_Or_Fixed_Point_Type (Ptr_To_Int'Result);

   function Bit_Cast (V, T : GL_Value; Name : String := "") return GL_Value is
     (Bit_Cast (V, Full_Etype (T), Name))
     with Pre  => Present (V) and then Present (T),
          Post => Present (Bit_Cast'Result);

   function Pointer_Cast
     (V, T : GL_Value; Name : String := "") return GL_Value is
     (Pointer_Cast (V, Full_Etype (T), Name))
     with Pre  => Present (V) and then Present (T),
          Post => Present (Pointer_Cast'Result);

   function Trunc (V, T : GL_Value; Name : String := "") return GL_Value is
     (Trunc (V, Etype (T), Name))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (T),
          Post => Is_Discrete_Or_Fixed_Point_Type (Trunc'Result);

   function S_Ext (V, T : GL_Value; Name : String := "") return GL_Value is
     (S_Ext (V, Etype (T), Name))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (T),
          Post => Is_Discrete_Or_Fixed_Point_Type (S_Ext'Result);

   function Z_Ext (V, T : GL_Value; Name : String := "") return GL_Value is
     (Z_Ext (V, Etype (T), Name))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (T),
          Post => Is_Discrete_Or_Fixed_Point_Type (Z_Ext'Result);

   function FP_Trunc (V, T : GL_Value; Name : String := "") return GL_Value is
     (FP_Trunc (V, Etype (T), Name))
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Floating_Point_Type (T),
          Post => Is_Floating_Point_Type (FP_Trunc'Result);

   function FP_Ext (V, T : GL_Value; Name : String := "") return GL_Value is
     (FP_Ext (V, Etype (T), Name))
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Floating_Point_Type (T),
          Post => Is_Floating_Point_Type (FP_Ext'Result);

   function FP_To_SI (V, T : GL_Value; Name : String := "") return GL_Value is
     (FP_To_SI (V, Etype (T), Name))
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (T),
          Post => Is_Discrete_Or_Fixed_Point_Type (FP_To_SI'Result);

   function FP_To_UI (V, T : GL_Value; Name : String := "") return GL_Value is
     (FP_To_UI (V, Etype (T), Name))
     with Pre  => Is_Floating_Point_Type (V)
                  and then Is_Discrete_Or_Fixed_Point_Type (T),
          Post => Is_Discrete_Or_Fixed_Point_Type (FP_To_UI'Result);

   function UI_To_FP (V, T : GL_Value; Name : String := "") return GL_Value is
     (UI_To_FP (V, Etype (T), Name))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Floating_Point_Type (T),
          Post => Is_Floating_Point_Type (UI_To_FP'Result);

   function SI_To_FP (V, T : GL_Value; Name : String := "") return GL_Value is
     (SI_To_FP (V, Etype (T), Name))
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                  and then Is_Floating_Point_Type (T),
          Post => Is_Floating_Point_Type (SI_To_FP'Result);

   procedure Store (Expr : GL_Value; Ptr : GL_Value)
     with Pre => Present (Expr)
                 and then Present (Ptr) and then Is_Access_Type (Ptr);

   function Load (Ptr : GL_Value; Name : String := "") return GL_Value
     with Pre  => Present (Ptr) and then Is_Access_Type (Ptr),
          Post => Present (Load'Result);

   function I_Cmp
     (Op       : Int_Predicate_T;
      LHS, RHS : GL_Value;
      Name     : String := "") return GL_Value
   is
     (G (I_Cmp (IR_Builder, Op, LLVM_Value (LHS), LLVM_Value (RHS), Name),
         Standard_Boolean))
     with Pre  => Present (LHS) and then Present (RHS),
          Post => Present (I_Cmp'Result);

   function F_Cmp
     (Op       : Real_Predicate_T;
      LHS, RHS : GL_Value;
      Name     : String := "") return GL_Value
   is
     (G (F_Cmp (IR_Builder, Op, LLVM_Value (LHS), LLVM_Value (RHS), Name),
         Standard_Boolean))
     with Pre  => Is_Floating_Point_Type (LHS)
                  and then Is_Floating_Point_Type (RHS),
          Post => Present (F_Cmp'Result);

   function NSW_Add
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
      (G_From (NSW_Add (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
               LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (NSW_Add'Result);

   function NSW_Sub
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (NSW_Sub (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (NSW_Sub'Result);

   function NSW_Mul
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     ((if RHS = Const_Int (RHS, Uint_1) then LHS
       elsif LHS = Const_Int (LHS, Uint_1) then RHS
       else G_From (NSW_Mul (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS),
                             Name),
                    LHS)))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (NSW_Mul'Result);

   function S_Div
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (S_Div (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (S_Div'Result);

   function U_Div
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (U_Div (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (U_Div'Result);

   function S_Rem
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (S_Rem (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (S_Rem'Result);

   function U_Rem
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (U_Rem (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (U_Rem'Result);

   function Build_And
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (Build_And (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (Build_And'Result);

   function Build_Or
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (Build_Or (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (Build_Or'Result);

   function Build_Xor
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (Build_Xor (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (LHS)
                   and then Is_Discrete_Or_Fixed_Point_Type (RHS),
           Post => Is_Discrete_Or_Fixed_Point_Type (Build_Xor'Result);

   function F_Add
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (F_Add (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Floating_Point_Type (LHS)
                   and then Is_Floating_Point_Type (RHS),
           Post => Is_Floating_Point_Type (F_Add'Result);

   function F_Sub
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (F_Sub (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Floating_Point_Type (LHS)
                   and then Is_Floating_Point_Type (RHS),
           Post => Is_Floating_Point_Type (F_Sub'Result);

   function F_Mul
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (F_Mul (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Floating_Point_Type (LHS)
                   and then Is_Floating_Point_Type (RHS),
           Post => Is_Floating_Point_Type (F_Mul'Result);

   function F_Div
     (LHS, RHS : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (F_Div (IR_Builder, LLVM_Value (LHS), LLVM_Value (RHS), Name),
              LHS))
      with Pre  => Is_Floating_Point_Type (LHS)
                   and then Is_Floating_Point_Type (RHS),
           Post => Is_Floating_Point_Type (F_Div'Result);

   function Shl
     (V, Count : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (Shl (IR_Builder, LLVM_Value (V), LLVM_Value (Count), Name), V))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                   and then Is_Discrete_Or_Fixed_Point_Type (Count),
           Post => Is_Discrete_Or_Fixed_Point_Type (Shl'Result);

   function L_Shr
     (V, Count : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (L_Shr (IR_Builder, LLVM_Value (V), LLVM_Value (Count), Name), V))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                   and then Is_Discrete_Or_Fixed_Point_Type (Count),
           Post => Is_Discrete_Or_Fixed_Point_Type (L_Shr'Result);

   function A_Shr
     (V, Count : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (A_Shr (IR_Builder, LLVM_Value (V), LLVM_Value (Count), Name), V))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (V)
                   and then Is_Discrete_Or_Fixed_Point_Type (Count),
           Post => Is_Discrete_Or_Fixed_Point_Type (A_Shr'Result);

   function Build_Not
     (V : GL_Value; Name : String := "") return GL_Value
   is
      (G_From (Build_Not (IR_Builder, LLVM_Value (V), Name), V))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (V),
           Post => Is_Discrete_Or_Fixed_Point_Type (Build_Not'Result);

   function NSW_Neg
     (V : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (NSW_Neg (IR_Builder, LLVM_Value (V), Name), V))
      with Pre  => Is_Discrete_Or_Fixed_Point_Type (V),
           Post => Is_Discrete_Or_Fixed_Point_Type (NSW_Neg'Result);

   function F_Neg
     (V : GL_Value; Name : String := "") return GL_Value
   is
     (G_From (F_Neg (IR_Builder, LLVM_Value (V), Name), V))
     with Pre  => Is_Floating_Point_Type (V),
          Post => Is_Floating_Point_Type (F_Neg'Result);

   function Build_Select
     (C_If, C_Then, C_Else : GL_Value; Name : String := "")
     return GL_Value
   is
     (G_From (Build_Select (IR_Builder, C_If => LLVM_Value (C_If),
                            C_Then => LLVM_Value (C_Then),
                            C_Else => LLVM_Value (C_Else), Name => Name),
              C_Then))
     with Pre  => Ekind (Full_Etype (C_If)) in Enumeration_Kind
                  and then Is_Elementary_Type (C_Then)
                  and then Is_Elementary_Type (C_Else),
          Post => Is_Elementary_Type (Build_Select'Result);

   procedure Build_Cond_Br
     (C_If : GL_Value; C_Then, C_Else : Basic_Block_T)
     with Pre => Ekind (Full_Etype (C_If)) in Enumeration_Kind
                 and then Present (C_Then) and then Present (C_Else);

   procedure Build_Ret (V : GL_Value)
     with Pre => Present (V);

   procedure Build_Ret_Void;

   procedure Build_Unreachable;

   function Build_Phi
     (GL_Values : GL_Value_Array;
      BBs       : Basic_Block_Array;
      Name      : String := "") return GL_Value
     with Pre  => GL_Values'First = BBs'First
                  and then GL_Values'Last = BBs'Last,
          Post => Present (Build_Phi'Result);

   function Int_To_Ref
     (V : GL_Value; TE : Entity_Id; Name : String := "")
     return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V) and then Is_Type (TE),
          Post => Is_Access_Type (Int_To_Ref'Result);
   --  Similar to Int_To_Ptr, but TE is the Designed_Type, not the
   --  access type.

   function Int_To_Raw_Array
     (V : GL_Value; TE : Entity_Id; Name : String := "")
     return GL_Value
     with Pre  => Is_Discrete_Or_Fixed_Point_Type (V) and then Is_Type (TE),
          Post => Is_Access_Type (Int_To_Raw_Array'Result)
                  and then Is_Raw_Array (Int_To_Raw_Array'Result);
   --  Similar to Int_To_Ptr, but TE is the Designed_Type, not the
   --  access type.

   function Extract_Value
     (Typ   : Entity_Id;
      Arg   : GL_Value;
      Index : unsigned;
      Name  : String := "") return GL_Value
   is
     (G (Extract_Value (IR_Builder, LLVM_Value (Arg), Index, Name), Typ))
     with  Pre  => Present (Arg) and then Is_Type (Typ),
           Post => Present (Extract_Value'Result);

   function Extract_Value_To_Ref
     (Typ   : Entity_Id;
      Arg   : GL_Value;
      Index : unsigned;
      Name  : String := "") return GL_Value
   is
     (G_Ref (Extract_Value (IR_Builder, LLVM_Value (Arg), Index, Name), Typ))
     with  Pre  => Present (Arg) and then Is_Type (Typ),
           Post => Is_Access_Type (Extract_Value_To_Ref'Result);

   function Extract_Value_To_Raw_Array
     (Typ   : Entity_Id;
      Arg   : GL_Value;
      Index : unsigned;
      Name  : String := "") return GL_Value
   is
     (G (Extract_Value (IR_Builder, LLVM_Value (Arg), Index, Name),
         Typ, Array_Data))
     with  Pre  => Present (Arg) and then Is_Type (Typ),
           Post => Is_Access_Type (Extract_Value_To_Raw_Array'Result);

   function Insert_Value
     (Arg, Elt : GL_Value;
      Index    : unsigned;
      Name     : String := "") return GL_Value
   is
     (G_From (Insert_Value (IR_Builder, LLVM_Value (Arg), LLVM_Value (Elt),
                            Index, Name),
              Arg))
     with  Pre  => Present (Arg) and then Present (Elt),
           Post => Present (Insert_Value'Result);

   type Index_Array is array (Integer range <>) of Natural;

   function Extract_Value
     (Typ     : Entity_Id;
      Arg     : GL_Value;
      Idx_Arr : Index_Array;
      Name    : String := "") return GL_Value
   is
     (G (Build_Extract_Value (IR_Builder, LLVM_Value (Arg),
                              Idx_Arr'Address, Idx_Arr'Length, Name),
         Typ))
     with  Pre  => Is_Type (Typ) and then Present (Arg),
           Post => Present (Extract_Value'Result);

   function Extract_Value_To_Ref
     (Typ     : Entity_Id;
      Arg     : GL_Value;
      Idx_Arr : Index_Array;
      Name    : String := "") return GL_Value
   is
     (G_Ref (Build_Extract_Value (IR_Builder, LLVM_Value (Arg),
                                  Idx_Arr'Address, Idx_Arr'Length, Name), Typ))
     with  Pre  => Is_Type (Typ) and then Present (Arg),
           Post => Present (Extract_Value_To_Ref'Result);

   function Extract_Value_To_Raw_Array
     (Typ     : Entity_Id;
      Arg     : GL_Value;
      Idx_Arr : Index_Array;
      Name    : String := "") return GL_Value
   is
     (G (Build_Extract_Value (IR_Builder, LLVM_Value (Arg),
                              Idx_Arr'Address, Idx_Arr'Length, Name),
         Typ, Array_Data))
     with  Pre  => Is_Type (Typ) and then Present (Arg),
           Post => Present (Extract_Value_To_Raw_Array'Result);

   function Insert_Value
     (Arg, Elt : GL_Value;
      Idx_Arr  : Index_Array;
      Name     : String := "") return GL_Value
   is
     (G_From (Build_Insert_Value (IR_Builder, LLVM_Value (Arg),
                                  LLVM_Value (Elt),
                                  Idx_Arr'Address, Idx_Arr'Length, Name),
              Arg))
     with  Pre  => Present (Arg) and then Present (Elt),
           Post => Present (Insert_Value'Result);

   function GEP
     (Result_Type : Entity_Id;
      Ptr         : GL_Value;
      Indices     : GL_Value_Array;
      Name        : String := "") return GL_Value
     with Pre  => Is_Access_Type (Ptr),
          Post => Is_Access_Type (GEP'Result);
   --  Helper for LLVM's Build_GEP

   function Call
     (Func        : GL_Value;
      Result_Type : Entity_Id;
      Args        : GL_Value_Array;
      Name        : String := "") return GL_Value
     with Pre  => Present (Func) and then Is_Type_Or_Void (Result_Type),
          Post => Present (Call'Result);

   function Call_Ref
     (Func        : GL_Value;
      Result_Type : Entity_Id;
      Args        : GL_Value_Array;
      Name        : String := "") return GL_Value
     with Pre  => Present (Func) and then Is_Type (Result_Type),
          Post => Is_Reference (Call_Ref'Result);

   procedure Call
     (Func : GL_Value; Args : GL_Value_Array; Name : String := "")
     with Pre  => Present (Func);

   function Inline_Asm
     (Args           : GL_Value_Array;
      Output_Value   : Entity_Id;
      Template       : String;
      Constraints    : String;
      Is_Volatile    : Boolean := False;
      Is_Stack_Align : Boolean := False) return GL_Value;

   function Block_Address
     (Func : GL_Value; BB : Basic_Block_T) return GL_Value is
      (G (Block_Address (LLVM_Value (Func), BB), Standard_A_Char))
     with Pre  => Present (Func) and then Present (BB),
          Post => Present (Block_Address'Result);

   function Build_Switch
     (V : GL_Value; Default : Basic_Block_T; Blocks : Nat) return Value_T is
     (Build_Switch (IR_Builder, LLVM_Value (V), Default, unsigned (Blocks)))
     with Pre  => Present (V) and then Present (Default),
          Post => Present (Build_Switch'Result);

   function Get_Type_Size (V : GL_Value) return GL_Value
     with Pre => Present (V), Post => Present (Get_Type_Size'Result);

   function Get_Type_Alignment (V : GL_Value) return unsigned
     with Pre => Present (V);

   function Add_Function
     (Name : String; T : Type_T; Return_TE : Entity_Id) return GL_Value is
     (G (Add_Function (LLVM_Module, Name, T),
         Return_TE, Reference_To_Subprogram))
     with Pre  => Present (T) and then Is_Type_Or_Void (Return_TE),
          Post => Present (Add_Function'Result);
   --  Add a function to the environment

   function Add_Global
     (TE             : Entity_Id;
      Name           : String;
      Need_Reference : Boolean := False) return GL_Value
     with Pre  => Is_Type (TE), Post => Present (Add_Global'Result);
     --  Add a global to the environment which is of type TE, so the global
     --  itself represents the address of TE.

   procedure Set_Initializer (V, Expr : GL_Value)
     with Pre => Present (V) and then Present (Expr);
   --  Set the initializer for a global variable

   procedure Set_Linkage (V : GL_Value; Linkage : Linkage_T)
     with Pre => Present (V);
   --  Set the linkage type for a variable

   procedure Set_Thread_Local (V : GL_Value; Thread_Local : Boolean)
     with Pre => Present (V);

end GNATLLVM.GLValue;

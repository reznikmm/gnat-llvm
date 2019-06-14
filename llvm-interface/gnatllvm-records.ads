------------------------------------------------------------------------------
--                             G N A T - L L V M                            --
--                                                                          --
--                     Copyright (C) 2013-2019, AdaCore                     --
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

with Sinfo;  use Sinfo;
with Table;  use Table;

with GNATLLVM.Environment; use GNATLLVM.Environment;
with GNATLLVM.GLType;      use GNATLLVM.GLType;
with GNATLLVM.GLValue;     use GNATLLVM.GLValue;
with GNATLLVM.Types;       use GNATLLVM.Types;

package GNATLLVM.Records is

   function Use_Discriminant_For_Bound (E : Entity_Id) return GL_Value
     with Pre  => Ekind (E) = E_Discriminant,
          Post => Present (Use_Discriminant_For_Bound'Result);
   --  E is an E_Discriminant that we've run into while emitting an expression.
   --  If we are expecting one as a possible bound, evaluate this discriminant
   --  as required to compute that bound.

   function Record_Field_Offset
     (V : GL_Value; Field : Entity_Id) return GL_Value
     with Pre  => Present (V)
                  and then Ekind_In (Field, E_Discriminant, E_Component),
          Post => Present (Record_Field_Offset'Result);
   --  Return a GL_Value that represents the offset of a given record field

   function Get_Record_Size_Complexity
     (TE : Entity_Id; Max_Size : Boolean := False) return Nat
     with Pre => Is_Record_Type (TE);
   --  Return the complexity of computing the size of a record.  This roughly
   --  gives the number of "things" needed to access to compute the size.
   --  This returns zero iff the record type is of a constant size.

   function Get_Record_Type_Size
     (TE         : Entity_Id;
      V          : GL_Value;
      Max_Size   : Boolean := False;
      No_Padding : Boolean := False) return GL_Value
     with Pre  => Is_Record_Type (TE),
          Post => Present (Get_Record_Type_Size'Result);
   --  Like Get_Type_Size, but only for record types

   function Get_Record_Type_Size
     (TE         : Entity_Id;
      V          : GL_Value;
      Max_Size   : Boolean := False;
      No_Padding : Boolean := False) return IDS
     with Pre  => Is_Record_Type (TE),
          Post => Present (Get_Record_Type_Size'Result);

   function Get_Record_Type_Size
     (TE         : Entity_Id;
      V          : GL_Value;
      Max_Size   : Boolean := False;
      No_Padding : Boolean := False) return BA_Data
     with Pre  => Is_Record_Type (TE);

   function Effective_Field_Alignment (F : Entity_Id) return Pos
     with Pre  => Ekind_In (F, E_Discriminant, E_Component);

   function Get_Record_Type_Alignment (TE : Entity_Id) return Nat
     with Pre => Is_Record_Type (TE);
   --  Like Get_Type_Alignment, but only for records and is called with
   --  the GNAT type.

   function Emit_Record_Aggregate
     (N : Node_Id; Result_So_Far : GL_Value) return GL_Value
     with Pre  => Nkind_In (N, N_Aggregate, N_Extension_Aggregate)
                  and then Is_Record_Type (Full_Etype (N)),
          Post => Present (Emit_Record_Aggregate'Result);
   --  Emit code for a record aggregate at Node.  Result_So_Far, if
   --  Present, contain any fields already filled in for the record.

   function Find_Matching_Field
     (TE : Entity_Id; Field : Entity_Id) return Entity_Id
     with Pre  => Is_Record_Type (TE)
     and then Ekind_In (Field, E_Discriminant, E_Component),
     Post => Chars (Field) = Chars (Find_Matching_Field'Result)
             and then Present (Get_Field_Info (Find_Matching_Field'Result));
   --  Find a field in the entity list of TE that has the same name as
   --  F and has Field_Info.

   function Contains_Unconstrained_Record (GT : GL_Type) return Boolean
     with Pre => Is_Record_Type (GT);
   --  True if TE has a field whose type if an unconstrained record.

   function Emit_Field_Position (E : Entity_Id; V : GL_Value) return GL_Value
     with Pre  => Ekind_In (E, E_Discriminant, E_Component),
          Post => No (Emit_Field_Position'Result)
                  or else (Type_Of (Emit_Field_Position'Result) =
                             LLVM_Size_Type);
   --  Compute and return the position in bits of the field specified
   --  by E from the start of its type as a value of Size_Type.  If
   --  Present, V is a value of that type, which is used in the case
   --  of a discriminated record.

   function Field_Ordinal (F : Entity_Id) return unsigned
     with Pre => Ekind_In (F, E_Component, E_Discriminant);
   --  Return the index of the field denoted by F. We assume here, but
   --  don't check, that the F is in a record with just a single RI.

   function Get_Field_Type (F : Entity_Id) return GL_Type
     with Pre  => Ekind_In (F, E_Component, E_Discriminant)
                  and then Present (Get_Field_Info (F)),
          Post => Present (Get_Field_Type'Result);
   --  Return the GL_Type of the field denoted by F

   function Field_Bit_Offset (F : Entity_Id) return Uint
     with Pre  => Ekind_In (F, E_Component, E_Discriminant)
                  and then Present (Get_Field_Info (F)),
          Post => Field_Bit_Offset'Result /= No_Uint;
   --  Return the bitfield offset of F or zero if it's not a bitfield

   function Is_Bitfield (F : Entity_Id) return Boolean
     with Pre  => Ekind_In (F, E_Component, E_Discriminant)
                  and then Present (Get_Field_Info (F));
   --  Indicate whether F is a bitfield, meaning that shift/mask operations
   --  are required to access it.

   function Is_Packable_Field (F : Entity_Id) return Boolean
     with Pre  => Ekind_In (F, E_Component, E_Discriminant);
   --  Indicate whether F is a field that we'll be packing.

   function Is_Bitfield_By_Rep
     (F            : Entity_Id;
      Pos          : Uint := No_Uint;
      Size         : Uint := No_Uint;
      Use_Pos_Size : Boolean := True) return Boolean
     with Pre => Ekind_In (F, E_Component, E_Discriminant);
   --  True if we need bitfield processing for this field based on its
   --  rep clause.  If Use_Pos_Size is specified, Pos and Size
   --  override that from F.

   function Is_Array_Bitfield (F : Entity_Id) return Boolean
     with Pre  => Ekind_In (F, E_Component, E_Discriminant)
                  and then Present (Get_Field_Info (F));
   --  If True, this is a bitfield and the underlying LLVM field is an
   --  array.  This means that we must use pointer-punning as part of
   --  accessing this field, which forces it in memory and means we can't
   --  do get a static access to this field.

   function Align_To
     (V : GL_Value; Cur_Align, Must_Align : Nat) return GL_Value
     with Pre => Present (V), Post => Present (Align_To'Result);
   --  V is a value aligned to Cur_Align.  Ensure that it's aligned to
   --  Align_To.

   function Build_Field_Load
     (In_V       : GL_Value;
      In_F       : Entity_Id;
      LHS        : GL_Value := No_GL_Value;
      For_LHS    : Boolean  := False;
      Prefer_LHS : Boolean  := False) return GL_Value
     with  Pre  => Is_Record_Type (Related_Type (In_V))
                   and then Ekind_In (In_F, E_Component, E_Discriminant),
           Post => Present (Build_Field_Load'Result);
   --  V represents a record.  Return a value representing loading field
   --  In_F from that record.  If For_LHS is True, this must be a reference
   --  to the field, otherwise, it may or may not be a reference, depending
   --  on what's simpler and the value of Prefer_LHS.

   function Build_Field_Store
     (LHS : GL_Value; In_F : Entity_Id; RHS : GL_Value) return GL_Value
     with  Pre => Is_Record_Type (Related_Type (LHS))
                  and then Present (RHS)
                  and then Ekind_In (In_F, E_Component, E_Discriminant);
   --  Likewise, but perform a store of RHS into the F component of LHS.
   --  If we return a value, that's the record that needs to be stored into
   --  the actual LHS.  If no value if returned, all our work is done.

   procedure Build_Field_Store
     (LHS : GL_Value; In_F : Entity_Id; RHS : GL_Value)
     with  Pre => Is_Record_Type (Related_Type (LHS))
                  and then Present (RHS)
                  and then Ekind_In (In_F, E_Component, E_Discriminant);
   --  Similar to the function version, but we always update LHS.

   procedure Perform_Writebacks;
   --  Perform any writebacks put onto the stack by the Add_Write_Back
   --  procedure.

   --  The following are debug procedures to print information about records
   --  and fields.

   procedure Print_Field_Info (E : Entity_Id)
     with Export, External_Name => "dfi";
   procedure Print_Record_Info (TE : Entity_Id)
     with Export, External_Name => "dri";

private

   --  We can't represent all records by a single native LLVM type, so we
   --  create two data structures to represent records and the positions of
   --  fields within the record.
   --
   --  The Record_Info type is the format of an entry in the
   --  Record_Info_Table, indexed by the Record_Info_Id type.  The
   --  Field_Info type is the format of an entry in the Field_Info_Table,
   --  indexed by the Field_Info_Id type.  Get_Record_Info applied to a
   --  record type points to a Record_Info_Id, which is the start of the
   --  description of the record. Get_Field_Info for each field points to a
   --  Field_Info_Id, which contains information about how to locate that
   --  field within the record.  Record_Info objects are chained.  For
   --  variant records, we use one chain for the common part of the record
   --  and chain for each variant.
   --
   --  The Record_Info data is used to compute the size of a record and, in
   --  conjunction with the Field_Info data, to determine the offset of a
   --  field from the start of an object of that record type.  We record
   --  information for each subtype separately.
   --
   --  A single Record_Info item can represent one of the following:
   --
   --      nothing, meaning that either the record or part of a variant
   --      record is empty
   --
   --      the variant part of a record
   --
   --      a single GL_Type, which must be a non-native (and hence usually
   --      of dynamic size)
   --
   --      a single LLVM type, which is a struct containing one or more
   --      fields
   --
   --  A Field_Info type locates a record by saying in which Record_Info
   --  piece it's located and, in the case where that piece contains an
   --  LLVM type, how to locate the field within that type.
   --
   --  A simple record (unpacked, with just scalar components) is
   --  represented by a single Record_Info item which points to the LLVM
   --  struct type corresponding to the Ada record.  More complex but
   --  non-variant cases containing variable-sized objects require a mix of
   --  Record_Info items corresponding to LLVM and GL types.  Note that a
   --  reference to a discriminant is handled within the description of
   --  array types.
   --
   --  For more complex records, the LLVM type generated may not directly
   --  correspond to that of the Ada type for two reasons.  First, the
   --  GL_Type of a field may have an alignment larger than the alignment
   --  of the native LLVM type of that field or there may be record rep
   --  clauses that creates holes either at the start of a record or
   --  between Ada fields.  In both of those cases, we add extra fields to
   --  the LLVM type to reflect the padding.
   --
   --  Secondly, LLVM doesn't support bitfields, so we have to do the work
   --  of generating the corresponding operations directly.  We make a
   --  field corresponding to a primitive scalar type with the proper size
   --  and alignments to represent one or more bit fields.  In the
   --  Field_Info item corresponding to each bitfield, we identify the
   --  ordinal of the field in the LLVM type as well as the starting bit
   --  position and bit size.
   --
   --  A fixed-size field may have an alignment requirement that's stricter
   --  than the alignment of the corresponding LLVM type, so we need to record
   --  the requested alignment in the Record_Info object.
   --
   --  For packed records, we use a packed LLVM struct type and also
   --  manually lay out fields that become bitfields.
   --
   --  For a variant part, we record the following in the corresponding
   --  Record_Info item:
   --
   --      A pointer to the GNAT tree for the variant part (to obtain the
   --      discriminant value corresponding to each variant)
   --
   --      The expression to be evaluated (which may be a reference to a
   --      discriminant) to determine which variant is present
   --
   --      An array of Record_Info chains (corresponding to the order in
   --      the GNAT tree) for each variant.  The offset of each of these
   --      chains starts at the offset of the variant Record_Info item.
   --
   --      An array of Record_Info items (in the same order) corresponding
   --      to any fields that are repped into a fixed position.  The
   --      relative offset of these fields is zero.

   type Record_Info_Base is record
      LLVM_Type        : Type_T;
      --  The LLVM type corresponding to this fragment, if any

      GT               : GL_Type;
      --  The GL_Type corresponding to this fragment, if any

      Align            : Nat;
      --  If specified, the alignment of this piece

      Position         : ULL;
      --  If nonzero, a forced starting position (in bits, but on a byte
      --  boundary) of this piece.  This can't be set on the first RI for a
      --  record.

      Next             : Record_Info_Id;
      --  Link to the next Record_Info entry for this record or variant

      Variant_List     : List_Id;
      --  List in GNAT tree of the variants for this fragment

      Variant_Expr     : Node_Id;
      --  Expression to evaluate to determine which variant is present

      Variants         : Record_Info_Id_Array_Access;
      --  Pointer to array of Record_Info_Ids representing the variants,
      --  which must be in the same order as in Variant_List.

      Overlap_Variants : Record_Info_Id_Array_Access;
      --  Likewise for any part of the variant who offset starts at
      --  the beginning of a record (for field with record rep
      --  clauses).
   end record;
   --  We want to put a Predicate on this, but can't, so we need to make
   --  a subtype for that purpose.

   function RI_Value_Is_Valid (RI : Record_Info_Base) return Boolean;
   --  Return whether a Record_Info value is valid or not

   subtype Record_Info is Record_Info_Base
     with Predicate => RI_Value_Is_Valid (Record_Info);

   package Record_Info_Table is new Table.Table
     (Table_Component_Type => Record_Info,
      Table_Index_Type     => Record_Info_Id'Base,
      Table_Low_Bound      => Record_Info_Low_Bound,
      Table_Initial        => 100,
      Table_Increment      => 50,
      Table_Name           => "Record_Info_Table");

   --  The information for a field is the index of the piece in the record
   --  information and optionally the location within the piece in the case
   --  when the Record_Info is an LLVM_type.  We also record the GL_Type
   --  used to represent the field and bit positions if this is a bitfield.

   type Field_Info is record
      Rec_Info_Idx   : Record_Info_Id;
      --  Index into the record info table that contains this field

      Field_Ordinal  : Nat;
      --  Ordinal of this field within the contents of the record info table

      GT             : GL_Type;
      --  The GL_Type correspond to this field, which takes into account
      --  a possible change in size

      First_Bit      : Uint;
      --  If not No_Uint, then the first bit (0-origin) within the LLVM field
      --  that corresponds to this field.

      Num_Bits       : Uint;
      --  If not No_Uint, then the number of bits within the LLVM field that
      --  corresponds to this field.

      Array_Bitfield : Boolean;
      --  If True, the underlying LLVM field is an array.  This means that we
      --  must use pointer-punning as part of accessing this field, which
      --  forces it in memory and means we can't do get a static access to
      --  this field.

   end record;

   package Field_Info_Table is new Table.Table
     (Table_Component_Type => Field_Info,
      Table_Index_Type     => Field_Info_Id'Base,
      Table_Low_Bound      => Field_Info_Low_Bound,
      Table_Initial        => 1000,
      Table_Increment      => 100,
      Table_Name           => "Record_Info_Table");

   function Get_Discriminant_Constraint
     (TE : Entity_Id; E : Entity_Id) return Node_Id
     with Pre  => Ekind (TE) = E_Record_Subtype,
          Post => Present (Get_Discriminant_Constraint'Result);
   --  Get the expression that constrains the discriminant E of type TE

   function Field_Position (E : Entity_Id; V : GL_Value) return BA_Data
     with Pre => Ekind_In (E, E_Component, E_Discriminant);
   --  Back-annotation version of Emit_Field_Position

end GNATLLVM.Records;

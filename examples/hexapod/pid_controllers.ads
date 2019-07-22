------------------------------------------------------------------------------
--                                                                          --
--                       Bare-Board Framework for Ada                       --
--                                                                          --
------------------------------------------------------------------------------
--                                                                          --
-- Copyright © 2019, Vadim Godunko <vgodunko@gmail.com>                     --
-- All rights reserved.                                                     --
--                                                                          --
-- Redistribution and use in source and binary forms, with or without       --
-- modification, are permitted provided that the following conditions       --
-- are met:                                                                 --
--                                                                          --
--  * Redistributions of source code must retain the above copyright        --
--    notice, this list of conditions and the following disclaimer.         --
--                                                                          --
--  * Redistributions in binary form must reproduce the above copyright     --
--    notice, this list of conditions and the following disclaimer in the   --
--    documentation and/or other materials provided with the distribution.  --
--                                                                          --
--  * Neither the name of the Vadim Godunko, IE nor the names of its        --
--    contributors may be used to endorse or promote products derived from  --
--    this software without specific prior written permission.              --
--                                                                          --
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS      --
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT        --
-- LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR    --
-- A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT     --
-- HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,   --
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED --
-- TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR   --
-- PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF   --
-- LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     --
-- NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS       --
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.             --
--                                                                          --
------------------------------------------------------------------------------

pragma Restrictions (No_Elaboration_Code);

package PID_Controllers is

   pragma Pure;

   type PID_Controller is private;

   procedure Initialize
     (Self         : in out PID_Controller;
      Proportional : Float;   --  proportional,
      Integral     : Float;   --  integral,
      Derivative   : Float;   --  derivative
      Min_Integral : Float;   --  Minimal integral value
      Max_Integral : Float);  --  Maximal integral value

   procedure Update
     (Self         : in out PID_Controller;
      Error        : Float;
      Elapsed_Time : Float;
      Output       : out Float);

private

   type PID_Controller is record
      Integral   : Float;
      Last_Error : Float;
      K_P : Float;   --  proportional,
      K_I : Float;   --  integral,
      K_D : Float;   --  derivative
      Min : Float;   --  Minimal integral value
      Max : Float;   --  Maximal integral value
   end record;

end PID_Controllers;

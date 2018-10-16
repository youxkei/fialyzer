open Base
open Ast_intf
open Obeam

module F = Abstract_format
         
let unit : expr = Val (Int 0)

let const_of_literal = function
  | F.LitAtom (_line_t, name) -> Atom name
  | LitInteger (_line_t, i) -> Int i
  | LitString (_line_t, s) -> String s
         
(* [e1; e2; ...] という式の列を let _ = e1 in let _ = e2 ... in という１つの式にする *)
let rec expr_of_exprs = function
  | [] -> unit
  | [e] -> e
  | e :: es ->
     Let ("_", e, expr_of_exprs es)

let rec expr_of_erlang_expr = function
  | F.ExprBody erlangs ->
     expr_of_exprs (List.map ~f:expr_of_erlang_expr erlangs)
  | ExprBinOp (_line_t, op, e1, e2) ->
     App(Var op, List.map ~f:expr_of_erlang_expr [e1; e2])
  | ExprVar (_line_t, v) -> Var v
  | ExprLit literal -> Val (const_of_literal literal)

let clauses_to_function = function
  | F.ClsCase(_line, _pattern, _guards, _body) ->
     failwith "not implemented: Clause Case"(* TODO : clause case *)
  | F.ClsFun(_line, args, _guards, body) ->
     let vs = args |> List.map ~f:(function F.PatVar (_,v) -> v | F.PatUniversal _ -> "_") in
     (vs, expr_of_erlang_expr body)
let forms_to_functions forms =
  forms
  |> List.filter_map ~f:(function F.DeclFun(line, name, arity, clauses) -> Some(line, name, arity, clauses) | _ -> None)
  |> List.map ~f:(fun (_line, name, arity, clauses) ->
                let spec = None in (* TODO : find spec of func *)
                let (vs, body) = clauses_to_function (List.hd_exn clauses) (* TODO : multi clauses function *) in
                (spec, name, vs, body))

let forms_to_module forms =
  let take_file forms =
    List.find_map ~f:(function F.AttrFile(line, file, line2) -> Some(line, file, line2) | _ -> None) forms
    |> Result.of_option ~error:(Failure "file attribute not found")
  in
  let take_module_name forms =
    List.find_map ~f:(function F.AttrMod(line, name) -> Some(line, name) | _ -> None) forms
    |> Result.of_option ~error:(Failure "module attribute not found")
  in
  let open Result in
  take_file forms >>= fun (_line, file, line2) ->
  take_module_name forms >>= fun (_line, name) ->
  let functions = forms_to_functions forms in
  let export = [] in (* TODO : take export functions *)
  Result.return {file; name; export; functions }

let code_to_module (F.AbstractCode form) =
  match form with
  | F.ModDecl forms ->
     forms_to_module forms
  | _ ->
     failwith "except for module decl, it is out of support"

let module_to_expr m =
  let funs =
    m.functions |> List.map ~f:(fun (_spec, name, args, body) ->
                              (name, Abs (args, body)))
  in
  Letrec(funs, unit)
  |> Result.return

let code_to_expr code =
  let open Result in
  code_to_module code >>= fun m ->
  module_to_expr m

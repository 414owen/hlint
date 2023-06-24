{-# LANGUAGE NamedFieldPuns #-}

module Hint.MagicNumber (magicNumberHint) where

import GHC.Hs hiding (Warning)
import GHC.Types.SrcLoc
import Data.Generics.Uniplate.DataOnly (universeBi)
import Config.Type(Severity(..))
import GHC.Data.Maybe (maybeToList)

import Hint.Type (DeclHint)
import Idea (Idea, rawIdea)

magicNumberHint :: DeclHint
magicNumberHint _ _ = concatMap warnMagicNum . universeBi

isBannedExpr :: HsExpr GhcPs -> Bool
isBannedExpr expr = case expr of
  NegApp _ (L _ sub) _ -> isBannedExpr sub
  HsLit _ lit -> isBannedLit lit
  HsPar _ _ (L _ sub) _ -> isBannedExpr sub
  HsOverLit _ (OverLit _ (HsIntegral _)) -> True
  HsOverLit _ (OverLit _ (HsFractional _)) -> True
  HsTypedBracket _ (L _ a) -> isBannedExpr a
  _ -> False

-- Some of these might only be generated by the compiler,
-- and not by user input, but I don't think that will matter,
-- as HLint will only see user-written literals
isBannedLit :: HsLit p -> Bool
isBannedLit lit = case lit of
  HsInt{} -> True
  HsIntPrim{} -> True
  HsWordPrim{} -> True
  HsInt64Prim{} -> True
  HsWord64Prim{} -> True
  HsInteger{} -> True
  _ -> False

mkWarning :: GenLocated (SrcSpanAnn' a) e -> [Idea]
mkWarning l = pure $ rawIdea Warning "Magic number" (getLocA l) "avoid magic numbers" Nothing [] []

warnComplexMagicNum :: LHsExpr GhcPs -> [Idea]
warnComplexMagicNum l@(L _ e)
  | isBannedExpr e = mkWarning l
  | otherwise = []

warnComplexMagicNums :: [LHsExpr GhcPs] -> [Idea]
warnComplexMagicNums = concatMap warnComplexMagicNum

warnMagicNumInTupleEl :: HsTupArg GhcPs -> [Idea]
warnMagicNumInTupleEl arg = case arg of
  Present _ el -> warnComplexMagicNum el
  _ -> []

warnMagicNumInMatchGroup :: LMatch GhcPs (LHsExpr GhcPs) -> [Idea]
warnMagicNumInMatchGroup (L _ (Match _ _ _ (GRHSs _ rhss _)))
  = warnGRHSNums rhss

warnGRHSNums :: [LGRHS GhcPs (LHsExpr GhcPs)] -> [Idea]
warnGRHSNums = concatMap warnGRHSNum

warnGRHSNum :: LGRHS GhcPs (LHsExpr GhcPs) -> [Idea]
warnGRHSNum (L _ (GRHS _ _ e)) = warnComplexMagicNum e

warnParStmts :: ParStmtBlock GhcPs GhcPs -> [Idea]
warnParStmts (ParStmtBlock _ stmts _ _) = warnMagicNumStmts stmts

warnMagicNumStmts :: [ExprLStmt GhcPs] -> [Idea]
warnMagicNumStmts = concatMap warnMagicNumStmt

warnMagicNumStmt :: ExprLStmt GhcPs -> [Idea]
warnMagicNumStmt (L _ s) = case s of
  LastStmt _ e _ _ -> warnComplexMagicNum e
  BindStmt _ _ e -> warnComplexMagicNum e
  -- I don't know what to do here, there doesn't seem to be
  -- an embedded HsExpr
  ApplicativeStmt{} -> []
  BodyStmt _ e _ _ -> warnComplexMagicNum e
  LetStmt _ _ -> []
  ParStmt _ parStmtBlcks _ _ ->
    -- warnComplexMagicNums e
    concatMap warnParStmts parStmtBlcks
  TransStmt{trS_stmts, trS_using, trS_by} ->
    warnMagicNumStmts trS_stmts
    <> warnComplexMagicNum trS_using
    <> concatMap warnComplexMagicNum (maybeToList trS_by)
  RecStmt{recS_stmts = L _ stmts} ->
    warnMagicNumStmts stmts

warnMagicArithSeqNum :: ArithSeqInfo GhcPs -> [Idea]
warnMagicArithSeqNum a = case a of
  From n -> warnComplexMagicNum n
  FromThen n m -> warnComplexMagicNums [n, m]
  FromTo n m -> warnComplexMagicNums [n, m]
  FromThenTo n m o -> warnComplexMagicNums [n, m, o]

warnMagicNum :: LHsExpr GhcPs -> [Idea]
warnMagicNum (L _ expr) = case expr of
  HsVar{} -> []
  HsUnboundVar{} -> []
  HsRecSel{} -> []
  HsOverLabel{} -> []
  HsIPVar{} -> []

  -- These are the things we're checking are magic, but
  -- we don't have enough context when we actually reach
  -- them, which is why we do it all a layer up.
  HsOverLit{} -> []
  HsLit{} -> []

  -- These are considered magic numbers if then contain
  -- a number in isBannedLit
  NegApp{} -> []
  HsPar{} -> []

  HsLam _ (MG _ (L _ alts)) -> concatMap warnMagicNumInMatchGroup alts
  HsLamCase _ _ (MG _ (L _ alts)) -> concatMap warnMagicNumInMatchGroup alts
  HsApp _ a b -> warnComplexMagicNums [a, b]
  HsAppType _ a _ _ -> warnComplexMagicNum a
  OpApp _ a b c -> warnComplexMagicNums [a, b, c]
  SectionL _ a b -> warnComplexMagicNums [a, b]
  SectionR _ a b -> warnComplexMagicNums [a, b]
  ExplicitTuple _ args _ -> concatMap warnMagicNumInTupleEl args
  ExplicitSum _ _ _ a -> warnComplexMagicNum a
  HsCase _ a (MG _ (L _ alts)) -> warnComplexMagicNum a <> concatMap warnMagicNumInMatchGroup alts
  HsIf _ a b c -> warnComplexMagicNums [a, b, c]
  HsMultiIf _ branches -> warnGRHSNums branches
  -- Non-magic number, because it's bound
  HsLet{} -> []
  HsDo _ _ (L _ stmts) -> warnMagicNumStmts stmts
  ExplicitList _ exprs -> warnComplexMagicNums exprs
  -- Intentionally non-magic numbers, as they have labels
  RecordCon{} -> []
  RecordUpd{} -> []
  HsGetField{gf_expr} -> warnComplexMagicNum gf_expr
  HsProjection{} -> []
  ExprWithTySig _ e _ -> warnComplexMagicNum e
  ArithSeq _ _ arith -> warnMagicArithSeqNum arith
  HsTypedBracket{} -> []
  HsUntypedBracket{} -> []
  HsTypedSplice _ e -> warnComplexMagicNum e
  HsUntypedSplice{} -> []
  HsProc{} -> []
  HsStatic _ e -> warnComplexMagicNum e
  HsPragE _ _ e -> warnComplexMagicNum e

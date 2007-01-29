module Kaos.ASTToCore (astToCore) where

import Kaos.Core
import Kaos.AST
import Kaos.Slot
import Kaos.KaosM
import Control.Monad.Writer
import Kaos.Typecheck
import Data.Generics

astToCore :: MonadKaos m => Statement Slot -> TypeCheckT m (Core Slot)
astToCore (SExpr e) = do
    (_, out) <- runWriterT $ expToCore e
    return out
astToCore (SBlock st) = fmap concat $ mapM astToCore st

emit x = tell [x]

type CoreWriter m a = WriterT (CoreBlock Slot) (TypeCheckT m) a

evalCond :: MonadKaos m => BoolExpr Slot -> CoreWriter m (BoolExpr Slot)
evalCond = everywhereM (mkM eval)
    where
        eval :: MonadKaos m => BoolExpr Slot -> CoreWriter m (BoolExpr Slot)
        eval (BCompare cmp e1 e2) = do
            s1 <- expToCore e1
            s2 <- expToCore e2
            s1 `sameType` s2
            return $ BCompare cmp (ELexical s1) (ELexical s2)
        eval x = return x

condToCore (BAnd e1 e2) = (cmpToCore e1) ++ [TokenLiteral "&&"] ++ condToCore e2
condToCore (BOr  e1 e2) = (cmpToCore e1) ++ [TokenLiteral "||"] ++ condToCore e2
condToCore e = cmpToCore e

cmpToCore (BCompare cmp (ELexical e1) (ELexical e2)) =
    [TokenSlot (SA e1 ReadAccess)
    ,TokenLiteral $ comparisonToCAOS cmp
    ,TokenSlot (SA e2 ReadAccess)
    ]
cmpToCore e = error $ "unexpected non-normal form: " ++ show e

expToCore :: MonadKaos m => Expression Slot -> CoreWriter m Slot
expToCore (EConst c) = do
    s <- newSlot
    s `typeIs` constType c
    emit $ CoreConst s c
    return s
expToCore (ELexical s) = return s
expToCore (EBinaryOp op e1 e2) = do
    s1   <- expToCore e1
    s2   <- expToCore e2
    dest <- newSlot
    s1 `sameType` s2
    s1 `sameType` dest
    emit $ CoreAssign dest s1
    emit $ CoreLine [ TokenLiteral op
                    , TokenSlot (SA dest MutateAccess)
                    , TokenSlot (SA s2   ReadAccess)
                    ]
    -- XXX type info
    return dest
expToCore (EAssign e1 e2) = do
    -- TODO: determine if e1 is mutable
    s1 <- expToCore e1
    s2 <- expToCore e2
    s1 `sameType` s2
    emit $ CoreAssign s1 s2
    return s1
expToCore (ECall "print" []) = 
    return $ error "XXX: void return"
expToCore (ECall "print" (h:t)) = do
    s <- expToCore h
    emit $ CoreTypeSwitch s (pt "outv" s) (pt "outs" s) pf
    expToCore (ECall "print" t)
    where
        pt verb slot = CoreLine [TokenLiteral verb, TokenSlot (SA slot ReadAccess)]
        pf = CoreLine [TokenLiteral "outs", TokenConst (CString "<object>")]
expToCore (ECall "sqrt" [e]) = do
    s <- expToCore e
    result <- newSlot
    s `sameType` result
    result `typeIs` typeNum
    emit $ CoreLine [ TokenLiteral "setv"
                    , TokenSlot (SA result WriteAccess)
                    , TokenLiteral "sqrt"
                    , TokenSlot (SA s ReadAccess)
                    ]
    return result
expToCore (ECall "__touch" [e]) = do
    s <- expToCore e
    emit $ CoreTouch (SA s MutateAccess)
    return s

expToCore (EBoolCast c) = do
    c' <- evalCond c
    let cexp = condToCore c'
    s  <- newSlot
    s `typeIs` typeNum

    emit $ CoreLine $
        [ TokenLiteral "doif" ] ++ cexp ++
        [ TokenLiteral "setv", TokenSlot (SA s WriteAccess), TokenConst (CInteger 1) ] ++
        [ TokenLiteral "else" ] ++
        [ TokenLiteral "setv", TokenSlot (SA s WriteAccess), TokenConst (CInteger 0) ] ++
        [ TokenLiteral "endi" ]
    return s

expToCore e = error $ "ICE: can't expToCore: " ++ show e


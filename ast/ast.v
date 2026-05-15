module ast

pub type Expr = CallExpr | Ident | StringLit | IntegerLit | FloatLit | InfixExpr | StructLiteral | PropertyAccess | MethodCall | ArrayLiteral | IndexExpr | BoolLit | PrefixExpr
pub type Stmt = ExprStmt | LetStmt | SpawnStmt | IfStmt | WhileStmt | ForStmt | StructDecl | ReturnStmt

pub struct ReturnStmt {
pub:
	value Expr
}

pub struct Program {
pub mut:
	functions []Function
	structs   []StructDecl
}

pub struct Param {
pub:
	name string
	typ  string
}

pub struct Function {
pub:
	name          string
	params        []Param
	receiver_name string
	receiver_type string
	body          Block
	is_gpu        bool
}

pub struct Block {
pub:
	statements []Stmt
}

pub struct LetStmt {
pub:
	name  Ident
	value Expr
}

pub struct ExprStmt {
pub:
	expr Expr
}

pub struct SpawnStmt {
pub:
	call CallExpr
}

pub struct IfStmt {
pub:
	condition   Expr
	consequence Block
	alternative Block
	has_else    bool
}

pub struct WhileStmt {
pub:
	condition Expr
	body      Block
}

pub struct ForStmt {
pub:
	var_name     Ident
	start        Expr
	end          Expr
	is_inclusive bool
	body         Block
}

pub struct Ident {
pub:
	value string
}

pub struct StringLit {
pub:
	value string
}

pub struct IntegerLit {
pub:
	value i64
}

pub struct BoolLit {
pub:
	value bool
}


pub struct InfixExpr {
pub:
	left  Expr
	op    string
	right Expr
}

pub struct PrefixExpr {
pub:
	op    string
	right Expr
}

pub struct FloatLit {
pub:
	value f64
}

pub struct CallExpr {
pub:
	function Ident
	args     []Expr
}

pub struct StructDecl {
pub:
	name   Ident
	fields []Ident
}

pub struct StructLiteral {
pub:
	name   Ident
	fields []Ident
	values []Expr
}

pub struct MethodCall {
pub:
	object Expr
	method Ident
	args   []Expr
}

pub struct PropertyAccess {
pub:
	object   Expr
	property Ident
}

pub struct ArrayLiteral {
pub:
	elements []Expr
}

pub struct IndexExpr {
pub:
	left  Expr
	index Expr
}

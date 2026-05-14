module lexer

pub enum TokenKind {
	eof
	illegal
	ident
	number
	string_lit
	plus
	minus
	asterisk
	slash
	assign
	lparen
	rparen
	lbrace
	rbrace
	comma
	semicolon
	lbracket
	rbracket
	dot
	colon
	// Keywords
	kw_fn
	kw_struct
	kw_let
	kw_return
	kw_spawn
	kw_gpu
	kw_if
	kw_else
	kw_while
	kw_for
	kw_from
	kw_to
	eq
	not_eq
	lt
	gt
	le
	ge
	bang
	kw_true
	kw_false
}

pub struct Token {
pub:
	kind TokenKind
	lit  string
	line int
	col  int
}

pub fn (t Token) str() string {
	return 'Token{kind: $t.kind, lit: "$t.lit", line: $t.line, col: $t.col}'
}

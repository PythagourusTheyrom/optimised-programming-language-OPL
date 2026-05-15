module lexer

pub struct Lexer {
mut:
	input    string
	pos      int
	read_pos int
	ch       u8
	line     int
	col      int
}

pub fn new(input string) &Lexer {
	mut l := &Lexer{
		input: input
		line: 1
		col: 0
	}
	l.read_char()
	return l
}

fn (mut l Lexer) read_char() {
	if l.read_pos >= l.input.len {
		l.ch = 0
	} else {
		l.ch = l.input[l.read_pos]
	}
	l.pos = l.read_pos
	l.read_pos++
	l.col++
}

pub fn (mut l Lexer) next_token() Token {
	l.skip_whitespace()
	
	mut tok := Token{line: l.line, col: l.col}
	
	match l.ch {
		0 { tok = Token{kind: .eof, lit: '', line: l.line, col: l.col} }
		`+` { tok = Token{kind: .plus, lit: '+', line: l.line, col: l.col} }
		`-` { tok = Token{kind: .minus, lit: '-', line: l.line, col: l.col} }
		`*` { tok = Token{kind: .asterisk, lit: '*', line: l.line, col: l.col} }
		`=` { 
			if l.peek_char() == `=` {
				l.read_char()
				tok = Token{kind: .eq, lit: '==', line: l.line, col: l.col}
			} else {
				tok = Token{kind: .assign, lit: '=', line: l.line, col: l.col}
			}
		}
		`!` {
			if l.peek_char() == `=` {
				l.read_char()
				tok = Token{kind: .not_eq, lit: '!=', line: l.line, col: l.col}
			} else {
				tok = Token{kind: .bang, lit: '!', line: l.line, col: l.col}
			}
		}
		`<` {
			if l.peek_char() == `=` {
				l.read_char()
				tok = Token{kind: .le, lit: '<=', line: l.line, col: l.col}
			} else {
				tok = Token{kind: .lt, lit: '<', line: l.line, col: l.col}
			}
		}
		`>` {
			if l.peek_char() == `=` {
				l.read_char()
				tok = Token{kind: .ge, lit: '>=', line: l.line, col: l.col}
			} else {
				tok = Token{kind: .gt, lit: '>', line: l.line, col: l.col}
			}
		}
		`(` { tok = Token{kind: .lparen, lit: '(', line: l.line, col: l.col} }
		`)` { tok = Token{kind: .rparen, lit: ')', line: l.line, col: l.col} }
		`{` { tok = Token{kind: .lbrace, lit: '{', line: l.line, col: l.col} }
		`}` { tok = Token{kind: .rbrace, lit: '}', line: l.line, col: l.col} }
		`,` { tok = Token{kind: .comma, lit: ',', line: l.line, col: l.col} }
		`;` { tok = Token{kind: .semicolon, lit: ';', line: l.line, col: l.col} }
		`[` { tok = Token{kind: .lbracket, lit: '[', line: l.line, col: l.col} }
		`]` { tok = Token{kind: .rbracket, lit: ']', line: l.line, col: l.col} }
		`.` { tok = Token{kind: .dot, lit: '.', line: l.line, col: l.col} }
		`:` { tok = Token{kind: .colon, lit: ':', line: l.line, col: l.col} }
		`/` {
			if l.peek_char() == `/` {
				l.read_char()
				for l.ch != 10 && l.ch != 0 {
					l.read_char()
				}
				return l.next_token()
			}
			tok = Token{kind: .slash, lit: "/", line: l.line, col: l.col}
		}
		else {
			if l.is_letter() {
				lit := l.read_identifier()
				tok = Token{kind: lookup_ident(lit), lit: lit, line: l.line, col: l.col}
				return tok
			} else if l.is_digit() {
				tok = Token{kind: .number, lit: l.read_number(), line: l.line, col: l.col}
				return tok
			} else if l.ch == `"` {
				tok = Token{kind: .string_lit, lit: l.read_string(), line: l.line, col: l.col}
				return tok
			} else {
				tok = Token{kind: .illegal, lit: l.ch.ascii_str(), line: l.line, col: l.col}
			}
		}
	}
	
	l.read_char()
	return tok
}

fn (l &Lexer) peek_char() u8 {
	if l.read_pos >= l.input.len {
		return 0
	}
	return l.input[l.read_pos]
}

fn (mut l Lexer) skip_whitespace() {
	for l.ch == ` ` || l.ch == `\t` || l.ch == `\n` || l.ch == `\r` {
		if l.ch == `\n` {
			l.line++
			l.col = 0
		}
		l.read_char()
	}
}

fn (mut l Lexer) is_letter() bool {
	return (l.ch >= `a` && l.ch <= `z`) || (l.ch >= `A` && l.ch <= `Z`) || l.ch == `_`
}

fn (mut l Lexer) is_digit() bool {
	return l.ch >= `0` && l.ch <= `9`
}

fn (mut l Lexer) read_identifier() string {
	start_pos := l.pos
	for l.is_letter() || l.is_digit() {
		l.read_char()
	}
	return l.input[start_pos..l.pos]
}

fn (mut l Lexer) read_number() string {
	start_pos := l.pos
	for l.is_digit() {
		l.read_char()
	}
	if l.ch == `.` {
		l.read_char()
		for l.is_digit() {
			l.read_char()
		}
	}
	// Bug 7: Support scientific notation
	if l.ch == `e` || l.ch == `E` {
		l.read_char()
		if l.ch == `+` || l.ch == `-` {
			l.read_char()
		}
		for l.is_digit() {
			l.read_char()
		}
	}
	return l.input[start_pos..l.pos]
}

fn (mut l Lexer) read_string() string {
	l.read_char() // skip opening quote
	start_pos := l.pos
	for l.ch != `"` && l.ch != 0 {
		l.read_char()
	}
	str := l.input[start_pos..l.pos]
	l.read_char() // skip closing quote
	return str
}

fn lookup_ident(ident string) TokenKind {
	return match ident {
		'fn' { .kw_fn }
		'let' { .kw_let }
		'return' { .kw_return }
		'spawn' { .kw_spawn }
		'gpu' { .kw_gpu }
		'if' { .kw_if }
		'else' { .kw_else }
		'while' { .kw_while }
		'for' { .kw_for }
		'struct' { .kw_struct }
		'from' { .kw_from }
		'to' { .kw_to }
		'until' { .kw_until }
		'true' { .kw_true }
		'false' { .kw_false }
		else { .ident }
	}
}

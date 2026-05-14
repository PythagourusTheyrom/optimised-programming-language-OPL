module parser

import lexer
import ast

pub struct Parser {
mut:
	l         &lexer.Lexer
	cur_tok   lexer.Token
	peek_tok  lexer.Token
}

pub fn new(mut l lexer.Lexer) &Parser {
	mut p := &Parser{
		l: l
	}
	p.next_token()
	p.next_token()
	return p
}

fn (mut p Parser) next_token() {
	p.cur_tok = p.peek_tok
	p.peek_tok = p.l.next_token()
}

pub fn (mut p Parser) parse_program() ast.Program {
	mut program := ast.Program{}
	for p.cur_tok.kind != .eof {
		if p.cur_tok.kind == .kw_fn || p.cur_tok.kind == .kw_gpu {
			program.functions << p.parse_function()
		} else if p.cur_tok.kind == .kw_struct {
			program.structs << p.parse_struct()
		} else {
			p.next_token()
		}
	}
	return program
}

fn (mut p Parser) parse_struct() ast.StructDecl {
	p.next_token() // skip 'struct'
	name := ast.Ident{value: p.cur_tok.lit}
	p.next_token() // skip name
	p.next_token() // skip '{'
	
	mut fields := []ast.Ident{}
	for p.cur_tok.kind != .rbrace && p.cur_tok.kind != .eof {
		fields << ast.Ident{value: p.cur_tok.lit}
		p.next_token() // skip ident
		if p.cur_tok.kind == .colon {
			p.next_token() // skip ':'
		}
		
		// Skip type (mandatory)
		if p.cur_tok.kind == .lbracket {
			p.next_token() // skip '['
			p.next_token() // skip type
			p.next_token() // skip ']'
		} else {
			p.next_token() // skip type
		}
		
		if p.cur_tok.kind == .comma {
			p.next_token() // skip ','
		}
	}
	p.next_token() // skip '}'
	return ast.StructDecl{name: name, fields: fields}
}

fn (mut p Parser) parse_function() ast.Function {
	mut is_gpu := false
	if p.cur_tok.kind == .kw_gpu {
		is_gpu = true
		p.next_token() // skip 'gpu'
	}
	p.next_token() // skip 'fn'
	
	mut receiver_name := ''
	mut receiver_type := ''
	
	if p.cur_tok.kind == .lparen {
		p.next_token() // skip '('
		receiver_name = p.cur_tok.lit
		p.next_token() // skip name
		receiver_type = p.cur_tok.lit
		p.next_token() // skip type
		p.next_token() // skip ')'
	}
	
	name := p.cur_tok.lit
	p.next_token() // skip name
	
	p.next_token() // skip '('
	mut params := []ast.Ident{}
	if p.cur_tok.kind != .rparen {
		for p.cur_tok.kind != .eof {
			params << ast.Ident{value: p.cur_tok.lit}
			p.next_token() // skip ident
			if p.cur_tok.kind != .comma && p.cur_tok.kind != .rparen {
				p.next_token() // skip type
			}
			if p.cur_tok.kind == .comma {
				p.next_token()
			} else {
				break
			}
		}
	}
	if p.cur_tok.kind == .rparen {
		p.next_token() // skip ')'
	}	
	body := p.parse_block()
	return ast.Function{
		name: name
		params: params
		receiver_name: receiver_name
		receiver_type: receiver_type
		body: body
		is_gpu: is_gpu
	}
}

fn (mut p Parser) parse_block() ast.Block {
	p.next_token() // skip '{'
	mut stmts := []ast.Stmt{}
	for p.cur_tok.kind != .rbrace && p.cur_tok.kind != .eof {
		stmts << p.parse_statement()
	}
	
	p.next_token() // skip '}'
	return ast.Block{statements: stmts}
}

fn (mut p Parser) parse_statement() ast.Stmt {
	if p.cur_tok.kind == .kw_spawn {
		p.next_token() // skip 'spawn'
		expr := p.parse_expression()
		if p.cur_tok.kind == .semicolon {
			p.next_token() // skip ';'
		}
		if expr is ast.CallExpr {
			return ast.SpawnStmt{call: expr as ast.CallExpr}
		}
		return ast.ExprStmt{expr: expr}
	} else if p.cur_tok.kind == .kw_let {
		p.next_token() // cur = name
		name := ast.Ident{value: p.cur_tok.lit}
		p.next_token() // cur = '='
		p.next_token() // cur = value
		
		expr := p.parse_expression()
		if p.cur_tok.kind == .semicolon {
			p.next_token() // skip ';'
		}
		return ast.LetStmt{name: name, value: expr}
	} else if p.cur_tok.kind == .kw_return {
		p.next_token() // skip 'return'
		expr := p.parse_expression()
		if p.cur_tok.kind == .semicolon {
			p.next_token() // skip ';'
		}
		return ast.ReturnStmt{value: expr}
	} else if p.cur_tok.kind == .kw_if {
		p.next_token() // skip 'if'
		cond := p.parse_expression()
		if cond is ast.InfixExpr {
			if cond.op == '=' {
				println("Parser Error: Illegal assignment in 'if' condition at line $p.cur_tok.line")
				exit(1)
			}
		}
		consequence := p.parse_block()
		mut has_else := false
		mut alternative := ast.Block{}
		if p.cur_tok.kind == .kw_else {
			has_else = true
			p.next_token()
			alternative = p.parse_block()
		}
		return ast.IfStmt{condition: cond, consequence: consequence, has_else: has_else, alternative: alternative}
	} else if p.cur_tok.kind == .kw_while {
		p.next_token() // skip 'while'
		cond := p.parse_expression()
		if cond is ast.InfixExpr {
			if cond.op == '=' {
				println("Parser Error: Illegal assignment in 'while' condition at line $p.cur_tok.line")
				exit(1)
			}
		}
		body := p.parse_block()
		return ast.WhileStmt{condition: cond, body: body}
	} else if p.cur_tok.kind == .kw_for {
		p.next_token() // skip 'for'
		var_name := p.cur_tok.lit
		p.next_token() // skip var name
		if p.cur_tok.lit != "from" {
			println("Error: Expected 'from' in for-loop, got '${p.cur_tok.lit}'")
		}
		p.next_token() // skip 'from'
		start := p.parse_expression()
		p.next_token() // skip 'to' (implied)
		end := p.parse_expression()
		body := p.parse_block()
		return ast.ForStmt{var_name: ast.Ident{value: var_name}, start: start, end: end, body: body}
	} else {
		expr := p.parse_expression()
		// Always ensure we move past the last token of the expression
		if p.cur_tok.kind == .semicolon {
			p.next_token() // skip ';'
		} else {
			p.next_token() // advance to next statement start
		}
		return ast.ExprStmt{expr: expr}
	}
}

fn (mut p Parser) parse_expression() ast.Expr {
	return p.parse_infix_expression(p.parse_primary_expression(), 0)
}

fn (mut p Parser) parse_primary_expression() ast.Expr {
	mut left := ast.Expr(ast.Ident{value: "error"})
	
	if p.cur_tok.kind == .eof {
		println("Unexpected EOF during parsing")
		exit(1)
	}
	
	if p.cur_tok.kind == .string_lit {
		left = ast.StringLit{value: p.cur_tok.lit}
		p.next_token()
	} else if p.cur_tok.kind == .number {
		if p.cur_tok.lit.contains('.') {
			left = ast.FloatLit{value: p.cur_tok.lit.f64()}
		} else {
			left = ast.IntegerLit{value: p.cur_tok.lit.int()}
		}
		p.next_token()
	} else if p.cur_tok.kind == .kw_true {
		left = ast.BoolLit{value: true}
		p.next_token()
	} else if p.cur_tok.kind == .kw_false {
		left = ast.BoolLit{value: false}
		p.next_token()
	} else if p.cur_tok.kind == .bang || p.cur_tok.kind == .minus {
		op := p.cur_tok.lit
		p.next_token()
		right := p.parse_infix_expression(p.parse_primary_expression(), 6) // High precedence for prefix
		return ast.PrefixExpr{op: op, right: right}
	} else if p.cur_tok.kind == .lbracket {
		p.next_token() // skip '['
		mut elements := []ast.Expr{}
		if p.cur_tok.kind != .rbracket {
			for p.cur_tok.kind != .eof {
				elements << p.parse_expression()
				// parse_expression advances to the next token (, or ])
				if p.cur_tok.kind == .comma {
					p.next_token() // cur = next expr
				} else {
					break
				}
			}
		}
		if p.cur_tok.kind == .rbracket {
			p.next_token()
		}
		left = ast.ArrayLiteral{elements: elements}
	} else if p.cur_tok.kind == .ident {
		ident := ast.Ident{value: p.cur_tok.lit}
		if p.peek_tok.kind == .lparen {
			p.next_token() // cur = '('
			p.next_token() // cur = first arg or ')'
			mut args := []ast.Expr{}
			if p.cur_tok.kind != .rparen {
				for p.cur_tok.kind != .eof {
					args << p.parse_expression()
					if p.cur_tok.kind == .comma {
						p.next_token() // cur = next expr
					} else {
						break
					}
				}
			}
			if p.cur_tok.kind == .rparen {
				p.next_token()
			}
			left = ast.CallExpr{function: ident, args: args}
		} else if p.peek_tok.kind == .lbrace {
			p.next_token() // cur = '{'
			p.next_token() // cur = first field or '}'
			mut fields := []ast.Ident{}
			mut values := []ast.Expr{}
			if p.cur_tok.kind != .rbrace {
				for p.cur_tok.kind != .eof {
					field_name := ast.Ident{value: p.cur_tok.lit}
					fields << field_name
					p.next_token() // skip field ident
					if p.cur_tok.kind == .colon {
						p.next_token() // skip ':'
					}
					values << p.parse_expression()
					if p.cur_tok.kind == .comma {
						p.next_token() // cur = next field
					} else {
						break
					}
				}
			}
			if p.cur_tok.kind == .rbrace {
				p.next_token()
			}
			left = ast.StructLiteral{name: ident, fields: fields, values: values}
		} else {
			left = ident
			p.next_token()
		}
	}
	
	// Handle Chaining: . and [
	for p.cur_tok.kind == .dot || p.cur_tok.kind == .lbracket {
		if p.cur_tok.kind == .dot {
			p.next_token() // cur = property/method name
			prop := ast.Ident{value: p.cur_tok.lit}
			
			if p.peek_tok.kind == .lparen {
				p.next_token() // cur = '('
				p.next_token() // cur = first arg or ')'
				mut args := []ast.Expr{}
				if p.cur_tok.kind != .rparen {
					for p.cur_tok.kind != .eof {
						args << p.parse_expression()
						if p.cur_tok.kind == .comma {
							p.next_token() // cur = next arg
						} else {
							break
						}
					}
				}
				if p.cur_tok.kind == .rparen {
					p.next_token() // skip ')'
				}
				left = ast.MethodCall{object: left, method: prop, args: args}
			} else {
				left = ast.PropertyAccess{object: left, property: prop}
				p.next_token() // skip property name
			}
		} else if p.cur_tok.kind == .lbracket {
			p.next_token() // cur = [
			index := p.parse_expression()
			if p.cur_tok.kind == .rbracket {
				p.next_token() // skip ]
			}
			left = ast.IndexExpr{left: left, index: index}
		}
	}
	
	return left
}

fn (mut p Parser) parse_infix_expression(left ast.Expr, precedence int) ast.Expr {
	mut res_left := left
	for precedence < p.get_precedence(p.cur_tok.kind) {
		op_tok := p.cur_tok
		p.next_token() // cur = right expr start
		right := p.parse_infix_expression(p.parse_primary_expression(), p.get_precedence(op_tok.kind))
		res_left = ast.InfixExpr{left: res_left, op: op_tok.lit, right: right}
	}
	return res_left
}

fn (p Parser) get_precedence(kind lexer.TokenKind) int {
	return match kind {
		.assign { 1 }
		.eq, .not_eq { 2 }
		.lt, .gt, .le, .ge { 3 }
		.plus, .minus { 4 }
		.asterisk, .slash { 5 }
		.dot { 6 }
		else { 0 }
	}
}


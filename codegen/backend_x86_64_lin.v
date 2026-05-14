module codegen

import ast

pub struct AsmX86_64Linux {
mut:
	text_section string
	data_section string
	str_count    int
	label_count    int
	variables      map[string]int
	stack_ptr      int
	struct_offsets map[string]int
}

pub fn new_x86_64_linux() &AsmX86_64Linux {
	return &AsmX86_64Linux{
		text_section: '.global main\n'
		data_section: '.section .rodata\n'
		variables: map[string]int{}
		stack_ptr: 0
		struct_offsets: map[string]int{}
	}
}

pub fn (mut c AsmX86_64Linux) generate(program ast.Program) string {
	for s in program.structs {
		for i, field in s.fields {
			c.struct_offsets[field.value] = i
		}
	}
	for func in program.functions {
		c.generate_function(func)
	}
	return c.text_section + '\n' + c.data_section
}

fn (mut c AsmX86_64Linux) generate_function(func ast.Function) {
	name := func.name
	
	if func.is_gpu {
		c.text_section += '; [GPU KERNEL START: ${func.name}]\n'
	}
	
	c.text_section += '$name:\n'
	c.text_section += '\tpush %rbp\n'
	c.text_section += '\tmov %rsp, %rbp\n'
	c.text_section += '\tsub $$144, %rsp\n' // 128 + 16 to keep 16-byte alignment
	
	c.variables = map[string]int{}
	c.stack_ptr = 8 
	
	for i, p in func.params {
		offset := c.stack_ptr
		c.variables[p.value] = offset
		// Save args from registers to stack
		if i == 0 { c.text_section += '\tmov %rdi, -${offset}(%rbp)\n' }
		if i == 1 { c.text_section += '\tmov %rsi, -${offset}(%rbp)\n' }
		if i == 2 { c.text_section += '\tmov %rdx, -${offset}(%rbp)\n' }
		if i == 3 { c.text_section += '\tmov %rcx, -${offset}(%rbp)\n' }
		if i == 4 { c.text_section += '\tmov %r8, -${offset}(%rbp)\n' }
		if i == 5 { c.text_section += '\tmov %r9, -${offset}(%rbp)\n' }
		c.stack_ptr += 8
	}
	
	for stmt in func.body.statements {
		c.generate_statement(stmt)
	}
	
	if func.name == 'main' {
		c.text_section += '\tmov $$0, %rax\n'
	}
	c.text_section += '\tmov %rbp, %rsp\n'
	c.text_section += '\tpop %rbp\n'
	c.text_section += '\tret\n\n'
}

fn (mut c AsmX86_64Linux) generate_statement(stmt ast.Stmt) {
	if stmt is ast.ExprStmt {
		c.generate_expression(stmt.expr)
	} else if stmt is ast.ReturnStmt {
		c.generate_expression(stmt.value)
		c.text_section += '\tmov %rbp, %rsp\n'
		c.text_section += '\tpop %rbp\n'
		c.text_section += '\tret\n'
	} else if stmt is ast.LetStmt {
		c.generate_expression(stmt.value)
		offset := c.stack_ptr
		c.variables[stmt.name.value] = offset
		c.text_section += '\tmov %rax, -${offset}(%rbp)\n'
		c.stack_ptr += 8
	} else if stmt is ast.SpawnStmt {
		func_name := stmt.call.function.value
		c.text_section += '\t# --- ASM NATIVE THREAD SPAWN ---\n'
		c.text_section += '\tsub $$16, %rsp\n'
		c.text_section += '\tlea (%rsp), %rdi\n'
		c.text_section += '\txor %rsi, %rsi\n'
		c.text_section += '\tlea ${func_name}(%rip), %rdx\n'
		c.text_section += '\txor %rcx, %rcx\n'
		c.text_section += '\tcall pthread_create\n'
		c.text_section += '\tmov (%rsp), %rdi\n'
		c.text_section += '\txor %rsi, %rsi\n'
		c.text_section += '\tcall pthread_join\n'
		c.text_section += '\tadd $$16, %rsp\n'
	} else if stmt is ast.IfStmt {
		c.generate_expression(stmt.condition)
		l_count := c.label_count
		c.label_count++
		c.text_section += '\tcmp $$0, %rax\n'
		c.text_section += '\tje .L_else_${l_count}\n'
		for s in stmt.consequence.statements {
			c.generate_statement(s)
		}
		c.text_section += '\tjmp .L_end_${l_count}\n'
		c.text_section += '.L_else_${l_count}:\n'
		if stmt.has_else {
			for s in stmt.alternative.statements {
				c.generate_statement(s)
			}
		}
		c.text_section += '.L_end_${l_count}:\n'
	} else if stmt is ast.WhileStmt {
		l_count := c.label_count
		c.label_count++
		c.text_section += '.L_while_cond_${l_count}:\n'
		c.generate_expression(stmt.condition)
		c.text_section += '\tcmp $$0, %rax\n'
		c.text_section += '\tje .L_while_end_${l_count}\n'
		for s in stmt.body.statements {
			c.generate_statement(s)
		}
		c.text_section += '\tjmp .L_while_cond_${l_count}\n'
		c.text_section += '.L_while_end_${l_count}:\n'
	} else if stmt is ast.ForStmt {
		c.generate_expression(stmt.start)
		offset := c.stack_ptr
		c.variables[stmt.var_name.value] = offset
		c.text_section += '\tmov %rax, -${offset}(%rbp)\n'
		c.stack_ptr += 8
		
		l_count := c.label_count
		c.label_count++
		c.text_section += '.L_for_cond_${l_count}:\n'
		c.generate_expression(stmt.end)
		c.text_section += '\tmov -${offset}(%rbp), %rcx\n'
		c.text_section += '\tcmp %rax, %rcx\n'
		c.text_section += '\tjge .L_for_end_${l_count}\n'
		
		for s in stmt.body.statements {
			c.generate_statement(s)
		}
		
		c.text_section += '\tmov -${offset}(%rbp), %rax\n'
		c.text_section += '\tadd $$1, %rax\n'
		c.text_section += '\tmov %rax, -${offset}(%rbp)\n'
		c.text_section += '\tjmp .L_for_cond_${l_count}\n'
		c.text_section += '.L_for_end_${l_count}:\n'
	}
}

fn (mut c AsmX86_64Linux) generate_expression(expr ast.Expr) {
	if expr is ast.IntegerLit {
		c.text_section += '\tmov $$${expr.value}, %rax\n'
	} else if expr is ast.Ident {
		if expr.value in c.variables {
			offset := c.variables[expr.value]
			c.text_section += '\tmov -${offset}(%rbp), %rax\n'
		}
	} else if expr is ast.InfixExpr {
		c.generate_expression(expr.left)
		c.text_section += '\tpush %rax\n'
		c.generate_expression(expr.right)
		c.text_section += '\tpop %rcx\n'
		
		// In pop %rcx, rcx is left, rax is right.
		if expr.op == '+' {
			c.text_section += '\tadd %rcx, %rax\n'
		} else if expr.op == '-' {
			c.text_section += '\tsub %rax, %rcx\n'
			c.text_section += '\tmov %rcx, %rax\n'
		} else if expr.op == '*' {
			c.text_section += '\timul %rcx, %rax\n'
		} else if expr.op == '<' {
			c.text_section += '\tcmp %rax, %rcx\n'
			c.text_section += '\tsetl %al\n'
			c.text_section += '\tmovzbq %al, %rax\n'
		} else if expr.op == '>' {
			c.text_section += '\tcmp %rax, %rcx\n'
			c.text_section += '\tsetg %al\n'
			c.text_section += '\tmovzbq %al, %rax\n'
		} else if expr.op == '==' {
			c.text_section += '\tcmp %rax, %rcx\n'
			c.text_section += '\tsete %al\n'
			c.text_section += '\tmovzbq %al, %rax\n'
		} else if expr.op == '=' {
			if expr.left is ast.Ident {
				offset := c.variables[expr.left.value]
				c.text_section += '\tmov %rax, -${offset}(%rbp)\n'
			} else if expr.left is ast.IndexExpr {
				c.text_section += '\tpush %rax\n'
				c.generate_expression(expr.left.left)
				c.text_section += '\tpush %rax\n'
				c.generate_expression(expr.left.index)
				c.text_section += '\tpop %rcx\n'
				c.text_section += '\timul $$8, %rax\n'
				c.text_section += '\tadd %rax, %rcx\n'
				c.text_section += '\tpop %rax\n'
				c.text_section += '\tmov %rax, (%rcx)\n'
			} else if expr.left is ast.PropertyAccess {
				c.text_section += '\tpush %rax\n'
				if expr.left.object is ast.Ident {
					offset := c.variables[expr.left.object.value]
					c.text_section += '\tlea -${offset}(%rbp), %rax\n'
				} else {
					c.generate_expression(expr.left.object)
				}
				offset := c.struct_offsets[expr.left.property.value] * 8
				c.text_section += '\tadd $$${offset}, %rax\n'
				c.text_section += '\tmov %rax, %rcx\n'
				c.text_section += '\tpop %rax\n'
				c.text_section += '\tmov %rax, (%rcx)\n'
			}
		}
	} else if expr is ast.ArrayLiteral {
		base_offset := c.stack_ptr
		c.stack_ptr += expr.elements.len * 8
		for i, el in expr.elements {
			c.generate_expression(el)
			offset := base_offset + (i * 8)
			c.text_section += '\tmov %rax, -${offset}(%rbp)\n'
		}
		c.text_section += '\tlea -${base_offset}(%rbp), %rax\n'
	} else if expr is ast.StructLiteral {
		base_offset := c.stack_ptr
		c.stack_ptr += expr.values.len * 8
		for i, val in expr.values {
			c.generate_expression(val)
			offset := base_offset + (i * 8)
			c.text_section += '\tmov %rax, -${offset}(%rbp)\n'
		}
		c.text_section += '\tlea -${base_offset}(%rbp), %rax\n'
	} else if expr is ast.IndexExpr {
		c.generate_expression(expr.left)
		c.text_section += '\tpush %rax\n'
		c.generate_expression(expr.index)
		c.text_section += '\tpop %rcx\n'
		c.text_section += '\timul $$8, %rax\n'
		c.text_section += '\tadd %rcx, %rax\n'
		c.text_section += '\tmov (%rax), %rax\n'
	} else if expr is ast.PropertyAccess {
		if expr.object is ast.Ident {
			offset := c.variables[expr.object.value]
			c.text_section += '\tlea -${offset}(%rbp), %rax\n'
		} else {
			c.generate_expression(expr.object)
		}
		offset := c.struct_offsets[expr.property.value] * 8
		c.text_section += '\tadd $$${offset}, %rax\n'
		c.text_section += '\tmov (%rax), %rax\n'
	} else if expr is ast.MethodCall {
		// Evaluate object (receiver)
		if expr.object is ast.Ident {
			offset := c.variables[(expr.object as ast.Ident).value]
			c.text_section += '\tlea -${offset}(%rbp), %rax\n'
		} else {
			c.generate_expression(expr.object)
		}
		c.text_section += '\tpush %rax\n'
		
		// Evaluate arguments
		for _, arg in expr.args {
			c.generate_expression(arg)
			c.text_section += '\tpush %rax\n'
		}
		
		// Pop arguments into registers
		num_args := expr.args.len
		for i := num_args; i >= 1; i-- {
			if i == 1 { c.text_section += '\tpop %rsi\n' }
			else if i == 2 { c.text_section += '\tpop %rdx\n' }
			else if i == 3 { c.text_section += '\tpop %rcx\n' }
			else if i == 4 { c.text_section += '\tpop %r8\n' }
			else if i == 5 { c.text_section += '\tpop %r9\n' }
		}
		c.text_section += '\tpop %rdi\n' // pop receiver into rdi
		
		func_name := expr.method.value
		c.text_section += '\tcall ${func_name}\n'
	} else if expr is ast.CallExpr {
		if expr.function.value == 'println' {
			if expr.args.len > 0 {
				arg := expr.args[0]
				if arg is ast.StringLit {
					str_label := 'str_${c.str_count}'
					c.str_count++
					c.data_section += '${str_label}: .asciz "${arg.value}\\n"\n'
					c.text_section += '\tlea ${str_label}(%rip), %rdi\n'
					c.text_section += '\txor %rax, %rax\n'
					c.text_section += '\tcall printf\n'
				} else {
					c.generate_expression(arg)
					// Simple heuristic: if it's PropertyAccess, it's likely a string in OPL bootstrap
					is_string := arg is ast.PropertyAccess || arg is ast.MethodCall
					if is_string {
						c.text_section += '\tmov %rax, %rdi\n'
						c.text_section += '\txor %rax, %rax\n'
						c.text_section += '\tcall printf\n'
					} else {
						c.text_section += '\tmov %rax, %rsi\n'
						if !c.data_section.contains('fmt_int:') {
							c.data_section += 'fmt_int: .asciz "%lld\\n"\n'
						}
						c.text_section += '\tlea fmt_int(%rip), %rdi\n'
						c.text_section += '\txor %rax, %rax\n'
						c.text_section += '\tcall printf\n'
					}
				}
			}
		} else {
			// Custom function call
			for _, arg in expr.args {
				c.generate_expression(arg)
				c.text_section += '\tpush %rax\n'
			}
			for i := expr.args.len - 1; i >= 0; i-- {
				if i == 0 { c.text_section += '\tpop %rdi\n' }
				else if i == 1 { c.text_section += '\tpop %rsi\n' }
				else if i == 2 { c.text_section += '\tpop %rdx\n' }
				else if i == 3 { c.text_section += '\tpop %rcx\n' }
				else if i == 4 { c.text_section += '\tpop %r8\n' }
				else if i == 5 { c.text_section += '\tpop %r9\n' }
				else { c.text_section += '\tadd $$8, %rsp\n' } // ignore extra for now
			}
			func_name := expr.function.value
			c.text_section += '\tcall ${func_name}\n'
		}
	}
}

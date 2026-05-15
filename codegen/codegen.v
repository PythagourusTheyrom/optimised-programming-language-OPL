module codegen

import ast
import os

pub struct Compiler {
mut:
	c_code string
}

pub fn new() &Compiler {
	mut c := &Compiler{
		c_code: '#include <stdio.h>\n#include <pthread.h>\n\n'
	}
	return c
}

pub fn (mut c Compiler) compile(program ast.Program) string {
	// Forward declarations
	for func in program.functions {
		if func.name == 'main' {
			c.c_code += 'int main();\n'
		} else {
			c.c_code += 'long long ${func.name}('
			for i, p in func.params {
				ctype := if p.typ == 'string' { 'char*' } else { 'long long' }
				c.c_code += '$ctype ${p.name}'
				if i < func.params.len - 1 {
					c.c_code += ', '
				}
			}
			c.c_code += ');\\n'
		}
	}
	
	// Thread wrappers
	for f in program.functions {
		c.c_code += 'void* __thread_${f.name}(void* arg) { ${f.name}('
		for i in 0 .. f.params.len {
			c.c_code += '0'
			if i < f.params.len - 1 {
				c.c_code += ', '
			}
		}
		c.c_code += '); return NULL; }\\n'
	}
	for f in program.functions {
		c.compile_function(f)
	}
	return c.c_code
}

fn (mut c Compiler) compile_function(f ast.Function) {
	if f.is_gpu {
		c.c_code += '// --- GPU KERNEL SIMULATION ---\n'
	}
	if f.name == 'main' {
		c.c_code += 'int main() {\n'
	} else {
		// Fix Bug 2: Return long long instead of void
		c.c_code += 'long long ${f.name}('
		for i, p in f.params {
			ctype := if p.typ == 'string' { 'char*' } else { 'long long' }
			c.c_code += '$ctype ${p.name}'
			if i < f.params.len - 1 {
				c.c_code += ', '
			}
		}
		c.c_code += ') {\n'
	}
	for stmt in f.body.statements {
		c.compile_statement(stmt)
	}
	if f.name == 'main' {
		c.c_code += '\treturn 0;\n'
	}
	c.c_code += '}\n'
}

fn (mut c Compiler) compile_statement(stmt ast.Stmt) {
	if stmt is ast.LetStmt {
		mut v_type := ''
		if stmt.value is ast.StringLit { v_type = 'char*' }
		else if stmt.value is ast.PropertyAccess {
			prop := stmt.value.property.value
			if prop == 'status' || prop == 'name' || prop == 'type' { v_type = 'string' }
			else if prop == 'size' || prop == 'count' || prop == 'id' { v_type = 'int' }
			else if prop == 'x' || prop == 'y' || prop == 'z' { v_type = 'float' }
		}
		else if stmt.value is ast.MethodCall {
			meth := stmt.value.method.value
			if meth == 'check' || meth == 'is_valid' { v_type = 'int' }
			else if meth == 'to_string' || meth == 'get_name' { v_type = 'string' }
			else if meth == 'get_value' || meth == 'calc' { v_type = 'float' }
		}
		else { v_type = 'long long' }
		
		c.c_code += '\t$v_type ${stmt.name.value} = '
		c.compile_expression(stmt.value)
		c.c_code += ';\n'
	} else if stmt is ast.ReturnStmt {
		c.c_code += '\treturn '
		c.compile_expression(stmt.value)
		c.c_code += ';\n'
	} else if stmt is ast.ExprStmt {
		c.c_code += '\t'
		c.compile_expression(stmt.expr)
		c.c_code += ';\n'
	} else if stmt is ast.SpawnStmt {
		c.c_code += '\tpthread_t thread_${stmt.call.function.value};\n'
		c.c_code += '\tpthread_create(&thread_${stmt.call.function.value}, NULL, __thread_${stmt.call.function.value}, NULL);\n'
		c.c_code += '\tpthread_join(thread_${stmt.call.function.value}, NULL);\n'
	} else if stmt is ast.IfStmt {
		c.c_code += '\tif ('
		c.compile_expression(stmt.condition)
		c.c_code += ') {\n'
		for s in stmt.consequence.statements {
			c.compile_statement(s)
		}
		c.c_code += '\t}\n'
		if stmt.has_else {
			c.c_code += '\telse {\n'
			for s in stmt.alternative.statements {
				c.compile_statement(s)
			}
			c.c_code += '\t}\n'
		}
	} else if stmt is ast.WhileStmt {
		c.c_code += '\twhile ('
		c.compile_expression(stmt.condition)
		c.c_code += ') {\n'
		for s in stmt.body.statements {
			c.compile_statement(s)
		}
		c.c_code += '\t}\n'
	} else if stmt is ast.ForStmt {
		c.c_code += '\tfor (long long ${stmt.var_name.value} = '
		c.compile_expression(stmt.start)
		c.c_code += '; ${stmt.var_name.value} < '
		c.compile_expression(stmt.end)
		c.c_code += '; ${stmt.var_name.value}++) {\n'
		for s in stmt.body.statements {
			c.compile_statement(s)
		}
		c.c_code += '\t}\n'
	}
}

fn (mut c Compiler) compile_expression(expr ast.Expr) {
	if expr is ast.FloatLit {
		c.c_code += '$expr.value'
	} else if expr is ast.IntegerLit {
		c.c_code += '$expr.value'
	} else if expr is ast.Ident {
		c.c_code += expr.value
	} else if expr is ast.InfixExpr {
		c.c_code += '('
		c.compile_expression(expr.left)
		c.c_code += ' $expr.op '
		c.compile_expression(expr.right)
		c.c_code += ')'
	} else if expr is ast.CallExpr {
		if expr.function.value == 'println' {
			// Bug 14: Support multiple arguments in println
			for i, arg in expr.args {
				// Better type detection for C backend println
				if arg is ast.StringLit {
					c.c_code += 'printf("%s", '
				} else if arg is ast.FloatLit {
					c.c_code += 'printf("%f", '
				} else {
					c.c_code += 'printf("%lld", (long long)' 
				}
				c.compile_expression(arg)
				c.c_code += '); printf(" ");'
			}
			c.c_code += ' printf("\\n")'
		} else {
			c.c_code += '${expr.function.value}('
			for i, arg in expr.args {
				c.compile_expression(arg)
				if i < expr.args.len - 1 {
					c.c_code += ', '
				}
			}
			c.c_code += ')'
		}
	}
}

pub fn (mut c Compiler) write_and_build(filename string) {
	c_filename := filename.replace('.opl', '.c')
	os.write_file(c_filename, c.c_code) or { panic(err) }
	
	exe_name := filename.replace('.opl', '')
	cmd := 'gcc -O3 -o $exe_name $c_filename'
	res := os.execute(cmd)
	if res.exit_code == 0 {
		println('Successfully built to executable: ./$exe_name')
		os.rm(c_filename) or { }
	} else {
		println('C Compilation Error:\n$res.output')
	}
}

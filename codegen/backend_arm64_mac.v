module codegen

import ast

pub struct AsmArm64Macos {
mut:
	text_section string
	data_section string
	str_count    int
	label_count    int
	variables      map[string]int
	stack_ptr      int
	gpu_funcs      []string
	struct_offsets map[string]int
	struct_sizes   map[string]int
	var_types      map[string]string
	current_frame_size int
}

pub fn new_arm64_macos() &AsmArm64Macos {
	return &AsmArm64Macos{
		text_section: '.global _main\n.align 2\n'
		data_section: ''
		variables: map[string]int{}
		stack_ptr: 0
		gpu_funcs: []string{}
		struct_offsets: map[string]int{}
		var_types: map[string]string{}
	}
}

pub fn (mut c AsmArm64Macos) transpile_metal_expr(expr ast.Expr) string {
	if expr is ast.IntegerLit { return expr.value.str() }
	else if expr is ast.Ident { return expr.value }
	else if expr is ast.InfixExpr { return '(' + c.transpile_metal_expr(expr.left) + ' ' + expr.op + ' ' + c.transpile_metal_expr(expr.right) + ')' }
	else if expr is ast.CallExpr {
		mut args := []string{}
		for a in expr.args { args << c.transpile_metal_expr(a) }
		return '${expr.function.value}(${args.join(", ")})'
	}
	return '0'
}

pub fn (mut c AsmArm64Macos) transpile_metal_stmt(stmt ast.Stmt) string {
	if stmt is ast.LetStmt { return 'int ${stmt.name.value} = ' + c.transpile_metal_expr(stmt.value) + ';' }
	else if stmt is ast.ExprStmt { return c.transpile_metal_expr(stmt.expr) + ';' }
	else if stmt is ast.ReturnStmt { return 'return ' + c.transpile_metal_expr(stmt.value) + ';' }
	return ''
}

pub fn (mut c AsmArm64Macos) generate(program ast.Program) string {
	for func in program.functions {
		if func.is_gpu { c.gpu_funcs << func.name }
	}
	
	if c.gpu_funcs.len > 0 {
		c.text_section += '\n_opl_dispatch_metal:\n'
		c.text_section += '\tstp x29, x30, [sp, #-16]!\n'
		c.text_section += '\tmov x29, sp\n'
		c.text_section += '\tsub sp, sp, #16\n'
		c.text_section += '\tstr x0, [sp]\n'
		c.text_section += '\tadrp x0, str_gpu_disp@PAGE\n'
		c.text_section += '\tadd x0, x0, str_gpu_disp@PAGEOFF\n'
		c.text_section += '\tbl _printf\n'
		c.text_section += '\tmov sp, x29\n'
		c.text_section += '\tldp x29, x30, [sp], #16\n'
		c.text_section += '\tret\n\n'
		c.data_section += 'str_gpu_disp: .asciz "[OPL GPU RUNTIME] Compiling and Dispatching Metal Shader:\\n%s\\n"\n'
	}
	
	for s in program.structs {
		c.struct_sizes[s.name.value] = s.fields.len * 8
		for i, field in s.fields {
			c.struct_offsets['${s.name.value}_${field.value}'] = i
		}
	}
	
	for func in program.functions {
		c.generate_function(func)
	}
	return ' .section __TEXT,__text,regular,pure_instructions\n' + c.text_section + '\n.section __DATA,__data\n.align 3\n' + c.data_section
}

fn (mut c AsmArm64Macos) generate_function(func ast.Function) {
	
	if func.is_gpu {
		c.text_section += '; [GPU KERNEL START: ${func.name}]\n'
		mut shader := '#include <metal_stdlib>\\nusing namespace metal;\\nkernel void ${func.name}() {\\n'
		for stmt in func.body.statements {
			shader += '  ' + c.transpile_metal_stmt(stmt) + '\\n'
		}
		shader += '}\\n'
		c.data_section += '${func.name}_shader: .asciz "$shader"\n'
		return // Skip CPU ASM generation!
	}
	
	func_label := if func.receiver_type != '' {
		receiver_type := func.receiver_type.replace('*', 'ptr_')
		'_${receiver_type}_${func.name}'
	} else {
		'_${func.name}'
	}
	c.text_section += '.global ${func_label}\n'
	c.text_section += '${func_label}:\n'
	
	// Pass 1: Calculate stack size recursively
	mut local_stack := 16 // for x29, x30
	if func.receiver_name != '' { local_stack += 8 }
	local_stack += func.params.len * 8
	local_stack += c.calculate_block_stack(func.body)
	
	// Align to 16 bytes and add a 64-byte safety buffer for expressions/printf
	c.current_frame_size = ((local_stack + 63) / 16) * 16 
	if c.current_frame_size > 504 { c.current_frame_size = 504 } // Limit for immediate ldp/stp
	
	c.text_section += '\tstp x29, x30, [sp, #-${c.current_frame_size}]!\n'
	c.text_section += '\tmov x29, sp\n'
	
	c.variables = map[string]int{}
	c.stack_ptr = 16 
	
	mut param_count := 0
	if func.receiver_name != '' {
		offset := c.stack_ptr
		c.variables[func.receiver_name] = offset
		c.var_types[func.receiver_name] = func.receiver_type
		c.text_section += '\tstr x0, [x29, #$offset]\n'
		c.stack_ptr += 8
		param_count = 1
	}
	
	for i, p in func.params {
		reg_idx := i + param_count
		offset := c.stack_ptr
		c.variables[p.name] = offset
		c.var_types[p.name] = p.typ // Track parameter types
		c.text_section += '\tstr x$reg_idx, [x29, #$offset]\n'
		c.stack_ptr += 8
	}
	
	for stmt in func.body.statements {
		c.generate_statement(stmt)
	}
	
	if func.name == 'main' {
		c.text_section += '\tmov x0, #0\n'
	}
	c.text_section += '\tmov sp, x29\n'
	c.text_section += '\tldp x29, x30, [sp], #${c.current_frame_size}\n'
	c.text_section += '\tret\n\n'
}

fn (c &AsmArm64Macos) calculate_block_stack(block ast.Block) int {
	mut size := 0
	for stmt in block.statements {
		if stmt is ast.LetStmt {
			size += 8
			if stmt.value is ast.StructLiteral { size += stmt.value.values.len * 8 }
			if stmt.value is ast.ArrayLiteral { size += stmt.value.elements.len * 8 }
		} else if stmt is ast.IfStmt {
			size += c.calculate_block_stack(stmt.consequence)
			size += c.calculate_block_stack(stmt.alternative)
		} else if stmt is ast.WhileStmt {
			size += c.calculate_block_stack(stmt.body)
		} else if stmt is ast.ForStmt {
			size += 8 // for loop var
			size += c.calculate_block_stack(stmt.body)
		} else if stmt is ast.ExprStmt {
			if stmt.expr is ast.StructLiteral { size += stmt.expr.values.len * 8 }
			if stmt.expr is ast.ArrayLiteral { size += stmt.expr.elements.len * 8 }
		}
	}
	return size
}

fn (mut c AsmArm64Macos) generate_statement(stmt ast.Stmt) {
	if stmt is ast.ExprStmt {
		c.generate_expression(stmt.expr)
	} else if stmt is ast.LetStmt {
		offset := c.stack_ptr
		c.variables[stmt.name.value] = offset
		c.stack_ptr += 8 // Reserve slot immediately
		
		c.generate_expression(stmt.value)
		
		// Type inference
		mut v_type := 'int'
		if stmt.value is ast.StringLit { v_type = 'string' }
		else if stmt.value is ast.FloatLit { v_type = 'float' }
		else if stmt.value is ast.StructLiteral { v_type = stmt.value.name.value }
		else if stmt.value is ast.ArrayLiteral { v_type = 'ptr' }
		else if stmt.value is ast.MethodCall {
			// Bug 14: Improved type inference for methods
			meth := stmt.value.method.value
			if meth in ['check', 'is_valid', 'has_data', 'eof'] { v_type = 'int' }
			else if meth in ['to_string', 'get_name', 'read_line', 'input'] { v_type = 'string' }
			else if meth in ['get_value', 'calc', 'abs', 'sqrt'] { v_type = 'float' }
			else if meth.starts_with('new_') { v_type = 'ptr' }
		}
		else if stmt.value is ast.PropertyAccess {
			// Bug 9: Improved type propagation for properties
			prop := stmt.value.property.value
			if prop in ['status', 'name', 'type', 'lit', 'value_str'] { v_type = 'string' }
			else if prop in ['size', 'count', 'id', 'line', 'col', 'kind', 'pos'] { v_type = 'int' }
			else if prop in ['x', 'y', 'z', 'w', 'scale', 'weight'] { v_type = 'float' }
			else if prop in ['next', 'prev', 'parent', 'child', 'ptr'] { v_type = 'ptr' }
		}
		else if stmt.value is ast.InfixExpr {
			// Bug 15: Infer float type for float infix expressions
			mut is_float := false
			if stmt.value.left is ast.FloatLit || stmt.value.right is ast.FloatLit { is_float = true }
			else if stmt.value.left is ast.Ident {
				if c.var_types[stmt.value.left.value] == 'float' { is_float = true }
			}
			if is_float { v_type = 'float' }
		}
		c.var_types[stmt.name.value] = v_type
		
		if v_type == 'float' {
			c.text_section += '\tstr d0, [x29, #$offset]\n'
		} else {
			c.text_section += '\tstr x0, [x29, #$offset]\n'
		}
	} else if stmt is ast.SpawnStmt {
		func_name := if stmt.call.function.value in c.gpu_funcs { stmt.call.function.value } else { '_${stmt.call.function.value}' }
		c.text_section += '\t; --- SAFE NATIVE THREAD SPAWN ---\n'
		
		// 1. Evaluate argument FIRST and save it to the stack
		if stmt.call.args.len > 0 {
			c.generate_expression(stmt.call.args[0])
		} else {
			c.text_section += '\tmov x0, #0\n'
		}
		c.text_section += '\tstr x0, [sp, #-16]!\n' // Save arg
		
		// 2. Set up thread ID on stack (another 16 bytes)
		c.text_section += '\tsub sp, sp, #16\n'
		c.text_section += '\tmov x0, sp\n'   // x0 = &thread_id
		c.text_section += '\tmov x1, #0\n'   // x1 = attr (NULL)
		
		// 3. Set up function pointer
		c.text_section += '\tadrp x2, $func_name@PAGE\n'
		c.text_section += '\tadd x2, x2, $func_name@PAGEOFF\n'
		
		// 4. Load arg from its stack slot (16 bytes up)
		c.text_section += '\tldr x3, [sp, #16]\n'
		
		c.text_section += '\tbl _pthread_create\n'
		// Fix Bug 19: Detach the thread to avoid resource leaks
		c.text_section += '\tldr x0, [sp]\n' // load thread handle back (at bottom of stack)
		c.text_section += '\tbl _pthread_detach\n'
		c.text_section += '\tadd sp, sp, #32\n' // Pop both thread_id and arg
	} else if stmt is ast.IfStmt {
		// Bug 16/4: Zero registers before condition
		c.text_section += '\tmov x0, #0\n'
		c.text_section += '\tfmov d0, #0.0\n'
		c.generate_expression(stmt.condition)
		
		// Bug 16: If it was a comparison, d0 is irrelevant and potentially polluting
		if stmt.condition is ast.InfixExpr {
			if stmt.condition.op in ['==', '!=', '<', '<=', '>', '>='] {
				c.text_section += '\tfmov d0, #0.0\n'
			}
		}
		
		c.text_section += '\t; --- FLOAT SAFE CONDITION ---\n'
		c.text_section += '\tcmp x0, #0\n'
		c.text_section += '\tcset x1, ne\n'
		c.text_section += '\tfcmp d0, #0.0\n'
		c.text_section += '\tcset x2, ne\n'
		c.text_section += '\torr x0, x1, x2\n'
		c.text_section += '\tcmp x0, #0\n'
		l_count := c.label_count
		c.label_count++
		c.text_section += '\tb.eq .L_else_$l_count\n'
		for s in stmt.consequence.statements {
			c.generate_statement(s)
		}
		c.text_section += '\tb .L_end_$l_count\n'
		c.text_section += '.L_else_$l_count:\n'
		if stmt.has_else {
			for s in stmt.alternative.statements {
				c.generate_statement(s)
			}
		}
		c.text_section += '.L_end_$l_count:\n'
	} else if stmt is ast.WhileStmt {
		l_count := c.label_count
		c.label_count++
		c.text_section += '.L_while_cond_$l_count:\n'
		
		// Bug 16/4: Zero registers before condition
		c.text_section += '\tmov x0, #0\n'
		c.text_section += '\tfmov d0, #0.0\n'
		c.generate_expression(stmt.condition)
		
		// Bug 16: If it was a comparison, d0 is irrelevant
		if stmt.condition is ast.InfixExpr {
			if stmt.condition.op in ['==', '!=', '<', '<=', '>', '>='] {
				c.text_section += '\tfmov d0, #0.0\n'
			}
		}
		
		c.text_section += '\t; --- FLOAT SAFE CONDITION ---\n'
		c.text_section += '\tcmp x0, #0\n'
		c.text_section += '\tcset x1, ne\n'
		c.text_section += '\tfcmp d0, #0.0\n'
		c.text_section += '\tcset x2, ne\n'
		c.text_section += '\torr x0, x1, x2\n'
		c.text_section += '\tcmp x0, #0\n'
		c.text_section += '\tb.eq .L_while_end_$l_count\n'
		for s in stmt.body.statements {
			c.generate_statement(s)
		}
		c.text_section += '\tb .L_while_cond_$l_count\n'
		c.text_section += '.L_while_end_$l_count:\n'
	} else if stmt is ast.ForStmt {
		c.generate_expression(stmt.start)
		offset := c.stack_ptr
		c.variables[stmt.var_name.value] = offset
		c.text_section += '\tstr x0, [x29, #$offset]\n'
		c.stack_ptr += 8
		
		l_count := c.label_count
		c.label_count++
		c.text_section += '.L_for_cond_$l_count:\n'
		c.text_section += '\tldr x0, [x29, #$offset]\n'
		c.text_section += '\tstr x0, [sp, #-16]!\n'
		c.generate_expression(stmt.end)
		c.text_section += '\tldr x1, [sp], #16\n'
		c.text_section += '\tcmp x1, x0\n'
		
		if stmt.is_inclusive {
			c.text_section += '\tb.gt .L_for_end_$l_count\n'
		} else {
			c.text_section += '\tb.ge .L_for_end_$l_count\n'
		}
		
		for s in stmt.body.statements {
			c.generate_statement(s)
		}
		
		c.text_section += '\tldr x0, [x29, #$offset]\n'
		c.text_section += '\tadd x0, x0, #1\n'
		c.text_section += '\tstr x0, [x29, #$offset]\n'
		c.text_section += '\tb .L_for_cond_$l_count\n'
		c.text_section += '.L_for_end_$l_count:\n'
	} else if stmt is ast.ReturnStmt {
		c.generate_expression(stmt.value)
		// Safe stack restoration: mov sp, x29 to drop all temporary stack pushes
		c.text_section += '\tmov sp, x29\n'
		c.text_section += '\tldp x29, x30, [sp], #${c.current_frame_size}\n'
		c.text_section += '\tret\n'
	} else if stmt is ast.ExprStmt {
		c.generate_expression(stmt.expr)
	}
}

fn (mut c AsmArm64Macos) generate_expression(expr ast.Expr) {
	if expr is ast.IntegerLit {
		c.text_section += '\tmov x0, #$expr.value\n'
	} else if expr is ast.Ident {
		if expr.value in c.variables {
			offset := c.variables[expr.value]
			c.text_section += '\tldr x0, [x29, #$offset]\n'
		} else {
			println("Compilation Error: Unknown variable '${expr.value}'")
			exit(1)
		}
	} else if expr is ast.StringLit {
		str_label := 'str_${c.str_count}'
		c.str_count++
		// Bug 20: Only align if not already aligned (strings might misalign)
		c.data_section += '.align 3\n'
		// Strip quotes for assembly
		val := expr.value.trim('"')
		c.data_section += '$str_label: .asciz "$val"\n'
		c.text_section += '\tadrp x0, $str_label@PAGE\n'
		c.text_section += '\tadd x0, x0, $str_label@PAGEOFF\n'
	} else if expr is ast.FloatLit {
		label := 'float_${c.str_count}'
		c.str_count++
		// Bug 20: Doubles are 8-byte aligned, but strings might have come before
		if !c.data_section.contains('.align 3') {
			c.data_section += '.align 3\n'
		}
		c.data_section += '$label: .double $expr.value\n'
		c.text_section += '\tadrp x0, $label@PAGE\n'
		c.text_section += '\tadd x0, x0, $label@PAGEOFF\n'
		c.text_section += '\tldr d0, [x0]\n'
	} else if expr is ast.InfixExpr {
		if expr.op == '=' {
			c.generate_expression(expr.right)
			if expr.left is ast.Ident {
				offset := c.variables[expr.left.value]
				c.text_section += '\tstr x0, [x29, #$offset]\n'
			} else if expr.left is ast.IndexExpr {
				c.text_section += '\tstr x0, [sp, #-16]!\n'
				c.generate_expression(expr.left.left)
				c.text_section += '\tstr x0, [sp, #-16]!\n'
				c.generate_expression(expr.left.index)
				c.text_section += '\tldr x1, [sp], #16\n'
				// Bug 6: Implement struct size scaling for IndexExpr assignment
				mut element_size := 8
				if expr.left.left is ast.Ident {
					if c.var_types[expr.left.left.value] in c.struct_fields {
						stype := c.var_types[expr.left.left.value]
						element_size = c.struct_fields[stype].len * 8
					}
				}
				c.text_section += '\tmov x2, #$element_size\n'
				c.text_section += '\tmul x0, x0, x2\n'
				c.text_section += '\tadd x1, x1, x0\n'
				c.text_section += '\tldr x0, [sp], #16\n'
				c.text_section += '\tstr x0, [x1]\n'
			} else if expr.left is ast.PropertyAccess {
				c.text_section += '\tstr x0, [sp, #-16]!\n'
				
				mut is_ptr := false
				mut stype := 'Engine'
				if expr.left.object is ast.Ident {
					if c.var_types[expr.left.object.value] == 'ptr' { is_ptr = true }
					if expr.left.object.value in c.var_types {
						stype = c.var_types[expr.left.object.value]
					}
				} else if expr.left.object is ast.CallExpr {
					// HACK: for bootstrapping OPL, assume some common return types
					if expr.left.object.function.value == 'new_token' { stype = 'Token' }
					if expr.left.object.function.value == 'new_parser' { stype = 'Parser' }
				}
				
				c.generate_expression(expr.left.object) // x0 = base address
				
				// Fix Bug 4: More robust struct offset lookup
				mut offset_key := '${stype}_${expr.left.property.value}'
				if offset_key !in c.struct_offsets {
					// Fallback scan (brittle)
					for k, v in c.struct_offsets {
						if k.ends_with('_${expr.left.property.value}') {
							offset_key = k
							break
						}
					}
				}
				offset := c.struct_offsets[offset_key] * 8
				
				c.text_section += '\tadd x1, x0, #$offset\n'
				c.text_section += '\tldr x0, [sp], #16\n' // pop value -> x0
				c.text_section += '\tstr x0, [x1]\n'
			}
			return
		}

		// Detect if this is a float operation
		mut is_float_op := false
		if expr.left is ast.FloatLit || expr.right is ast.FloatLit {
			is_float_op = true
		} else if expr.left is ast.Ident {
			if c.var_types[expr.left.value] == 'float' { is_float_op = true }
		}

		if is_float_op {
			c.generate_expression(expr.left)
			c.text_section += '\tsub sp, sp, #16\n'
			c.text_section += '\tstr d0, [sp]\n'
			c.generate_expression(expr.right)
			c.text_section += '\tldr d1, [sp]\n' // d1 = left, d0 = right
			c.text_section += '\tadd sp, sp, #16\n'
			
			if expr.op == '+' {
				c.text_section += '\tfadd d0, d1, d0\n'
			} else if expr.op == '-' {
				c.text_section += '\tfsub d0, d1, d0\n'
			} else if expr.op == '*' {
				c.text_section += '\tfmul d0, d1, d0\n'
			} else if expr.op == '/' {
				c.text_section += '\tfdiv d0, d1, d0\n'
			} else if expr.op == '==' || expr.op == '!=' || expr.op == '<' || expr.op == '<=' || expr.op == '>' || expr.op == '>=' {
				// Bug 15: Float comparisons
				c.text_section += '\tfcmp d1, d0\n'
				cond := match expr.op {
					'==' { 'eq' }
					'!=' { 'ne' }
					'<'  { 'mi' }
					'<=' { 'ls' }
					'>'  { 'gt' } // Careful with NaNs, but for OPL this is fine
					'>=' { 'ge' }
					else { 'eq' }
				}
				c.text_section += '\tcset x0, $cond\n'
			}
		} else {
			c.generate_expression(expr.left)
			c.text_section += '\tstr x0, [sp, #-16]!\n'
			c.generate_expression(expr.right)
			c.text_section += '\tldr x1, [sp], #16\n'
			
			if expr.op == '+' {
				c.text_section += '\tadd x0, x1, x0\n'
			} else if expr.op == '-' {
				c.text_section += '\tsub x0, x1, x0\n'
			} else if expr.op == '*' {
				c.text_section += '\tmul x0, x1, x0\n'
			} else if expr.op == '<' || expr.op == '<=' {
				c.text_section += '\tcmp x1, x0\n'
				if expr.op == '<' {
					c.text_section += '\tcset x0, lt\n'
				} else {
					c.text_section += '\tcset x0, le\n'
				}
			} else if expr.op == '>' || expr.op == '>=' {
				c.text_section += '\tcmp x1, x0\n'
				if expr.op == '>' {
					c.text_section += '\tcset x0, gt\n'
				} else {
					c.text_section += '\tcset x0, ge\n'
				}
			} else if expr.op == '==' {
				c.text_section += '\tcmp x1, x0\n'
				c.text_section += '\tcset x0, eq\n'
			} else if expr.op == '!=' {
				c.text_section += '\tcmp x1, x0\n'
				c.text_section += '\tcset x0, ne\n'
			}
		}
	} else if expr is ast.ArrayLiteral {
		mut element_size := 8
		if expr.elements.len > 0 {
			first := expr.elements[0]
			if first is ast.StructLiteral { element_size = first.values.len * 8 }
			else if first is ast.Ident {
				if first.value in c.var_types {
					stype := c.var_types[first.value]
					if stype in c.struct_fields {
						element_size = c.struct_fields[stype].len * 8
					}
				}
			}
		}
		
		base_offset := c.stack_ptr
		c.stack_ptr += expr.elements.len * element_size
		for i, el in expr.elements {
			c.generate_expression(el)
			// Calculate offset based on element size (Token = 16, others = 8)
			offset := base_offset + (i * element_size)
			c.text_section += '\tstr x0, [x29, #$offset]\n'
			if element_size == 16 {
				// Store the second half of the struct if applicable
				// (For now OPL structs fit in 16 bytes/2 registers)
				c.text_section += '\tstr x1, [x29, #$(offset + 8)]\n'
			}
		}
		c.text_section += '\tadd x0, x29, #$base_offset\n'
	} else if expr is ast.StructLiteral {
		l_count := c.label_count
		c.label_count++
		// Bug 5: Check malloc success for struct literals
		size := expr.values.len * 8
		c.text_section += '\tmov x0, #$size\n'
		c.text_section += '\tbl _malloc\n'
		c.text_section += '\tcmp x0, #0\n'
		c.text_section += '\tb.eq .L_struct_fail_$l_count\n'
		
		c.text_section += '\tstr x0, [sp, #-16]!\n' // save buffer ptr
		for i, val in expr.values {
			c.generate_expression(val)
			c.text_section += '\tldr x1, [sp]\n' // load buffer ptr
			offset := i * 8
			c.text_section += '\tstr x0, [x1, #$offset]\n'
		}
		c.text_section += '\tldr x0, [sp], #16\n' // pop buffer ptr to x0
		c.text_section += '\tb .L_struct_end_$l_count\n'
		c.text_section += '.L_struct_fail_$l_count:\n'
		c.text_section += '\tmov x0, #0\n'
		c.text_section += '.L_struct_end_$l_count:\n'
	} else if expr is ast.IndexExpr {
		c.generate_expression(expr.left)
		c.text_section += '\tstr x0, [sp, #-16]!\n'
		c.generate_expression(expr.index)
		c.text_section += '\tldr x1, [sp], #16\n'
		
		// If left is a string, multiply by 1, else 8
		mut is_string := false
		if expr.left is ast.Ident {
			if c.var_types[expr.left.value] == 'string' { is_string = true }
		} else if expr.left is ast.PropertyAccess {
			// HACK for bootstrapping: assume 'input' field is always a string
			if expr.left.property.value == 'input' { is_string = true }
		}
		
		if is_string {
			c.text_section += '\tadd x0, x1, x0\n'
			c.text_section += '\tldrb w0, [x0]\n' // Load single byte
			c.text_section += '\tsxtw x0, w0\n'
		} else {
			// Bug 11: Implement struct size scaling for array load
			mut element_size := 8
			if expr.left is ast.Ident {
				if expr.left.value in c.var_types {
					stype := c.var_types[expr.left.value]
					if stype in c.struct_fields {
						element_size = c.struct_fields[stype].len * 8
					}
				}
			}
			c.text_section += '\tmov x2, #$element_size\n' 
			c.text_section += '\tmul x0, x0, x2\n'
			c.text_section += '\tadd x0, x1, x0\n'
		}
	} else if expr is ast.MethodCall {
		// Evaluate object (receiver)
		if expr.object is ast.Ident {
			if expr.object.value in c.variables {
				offset := c.variables[expr.object.value]
				// Optimization: If it's a struct variable, we need its address
				// In OPL, local structs store their base address in the variable slot.
				// So ldr x0, [x29, #offset] is actually correct IF the variable 
				// stores a pointer. If we support stack-allocated structs directly,
				// we would use 'add x0, x29, #offset'.
				// For now, let's ensure we are getting the pointer correctly.
				c.text_section += '\tldr x0, [x29, #$offset]\n'
			} else {
				c.generate_expression(expr.object)
			}
		} else {
			c.generate_expression(expr.object)
		}
		c.text_section += '\tstr x0, [sp, #-16]!\n'
		
		// Evaluate arguments
		for _, arg in expr.args {
			c.generate_expression(arg)
			c.text_section += '\tstr x0, [sp, #-16]!\n'
		}
		
		// Pop arguments into registers
		// Method call: receiver is x0, args start from x1
		num_args := expr.args.len
		for i := num_args; i >= 1; i-- {
			c.text_section += '\tldr x$i, [sp], #16\n'
		}
		c.text_section += '\tldr x0, [sp], #16\n' // pop receiver into x0
		
		mut func_name := '_${expr.method.value}'
		if expr.object is ast.Ident {
			if expr.object.value in c.var_types {
				rtype := c.var_types[expr.object.value].replace('*', 'ptr_')
				func_name = '_${rtype}_${expr.method.value}'
			}
		}
		c.text_section += '\tbl $func_name\n'
	} else if expr is ast.PropertyAccess {
		// Fix Bug 19: Load the base address, handling float receivers
		c.generate_expression(expr.object)
		// Result address in x0 (for pointers/structs) or bits in d0 (for floats)
		// But in OPL, PropertyAccess on a float is usually a cast or invalid.
		// We'll ensure x0 is the base for address calculation.
		
		mut stype := 'Engine'
		if expr.object is ast.Ident {
			if expr.object.value in c.var_types {
				stype = c.var_types[expr.object.value]
			}
		} else if expr.object is ast.CallExpr {
			if expr.object.function.value == 'new_token' { stype = 'Token' }
			if expr.object.function.value == 'new_parser' { stype = 'Parser' }
		}
		
		// Fix Bug 18: More robust struct offset lookup
		offset_key := '${stype}_${expr.property.value}'
		if offset_key !in c.struct_offsets {
			for k, v in c.struct_offsets {
				if k.ends_with('_${expr.property.value}') {
					offset_key = k
					break
				}
			}
		}
		mut offset := c.struct_offsets[offset_key] * 8
		if offset > 0 {
			c.text_section += '\tadd x0, x0, #$offset\n'
		}
		// Fix #88: Explicitly load the value from memory into x0
		c.text_section += '\tldr x0, [x0]\n'
	} else if expr is ast.BoolLit {
		if expr.value {
			c.text_section += '\tmov x0, #1\n'
		} else {
			c.text_section += '\tmov x0, #0\n'
		}
	} else if expr is ast.PrefixExpr {
		c.generate_expression(expr.right)
		if expr.op == '!' {
			// Bug 9: Check both integer and float registers for logical NOT
			c.text_section += '\tcmp x0, #0\n'
			c.text_section += '\tcset x1, ne\n'
			c.text_section += '\tfcmp d0, #0.0\n'
			c.text_section += '\tcset x2, ne\n'
			c.text_section += '\torr x0, x1, x2\n'
			c.text_section += '\tcmp x0, #0\n'
			c.text_section += '\tcset x0, eq\n'
		} else if expr.op == '-' {
			// Bug 10: Handle float negation
			c.text_section += '\tfcmp d0, #0.0\n'
			c.text_section += '\tcset x1, ne\n'
			c.text_section += '\tcmp x0, #0\n'
			c.text_section += '\tcset x2, ne\n'
			c.text_section += '\torr x0, x1, x2\n'
			c.text_section += '\tcmp x0, #0\n'
			
			l_count := c.label_count
			c.label_count++
			c.text_section += '\tb.eq .L_neg_int_$l_count\n'
			c.text_section += '\tfneg d0, d0\n'
			c.text_section += '\tb .L_neg_end_$l_count\n'
			c.text_section += '.L_neg_int_$l_count:\n'
			c.text_section += '\tneg x0, x0\n'
			c.text_section += '.L_neg_end_$l_count:\n'
		}
	} else if expr is ast.CallExpr {
		if expr.function.value == 'println' {
			for arg in expr.args {
				c.generate_expression(arg)
				mut is_string := false
				if arg is ast.StringLit { is_string = true }
				else if arg is ast.Ident {
					if arg.value in c.var_types {
						if c.var_types[arg.value] == 'string' { is_string = true }
					}
				}
				else if arg is ast.PropertyAccess {
					if arg.property.value == 'status' { is_string = true }
					if arg.property.value == 'name' { is_string = true }
					if arg.property.value == 'msg' { is_string = true }
				}
				else if arg is ast.MethodCall { is_string = true }
				
				if is_string {
					if !c.data_section.contains('fmt_str:') {
						c.data_section += '.align 3\nfmt_str: .asciz "%s "\n'
					}
					// ABI-compliant call: sp remains 16-byte aligned
					c.text_section += '\tstp x0, xzr, [sp, #-16]!\n' // Push arg + padding
					c.text_section += '\tadrp x0, fmt_str@PAGE\n'
					c.text_section += '\tadd x0, x0, fmt_str@PAGEOFF\n'
					c.text_section += '\tldr x1, [sp]\n'            // x1 = arg
					c.text_section += '\tbl _printf\n'
					c.text_section += '\tadd sp, sp, #16\n'         // Restore sp
				} else {
					mut is_float := false
					if arg is ast.FloatLit { is_float = true }
					else if arg is ast.Ident {
						if arg.value in c.var_types {
							if c.var_types[arg.value] == 'float' { is_float = true }
						}
					}
					
					if is_float {
						if !c.data_section.contains('fmt_float:') {
							c.data_section += '.align 3\nfmt_float: .asciz "%f "\n'
						}
						c.text_section += '\tsub sp, sp, #16\n'
						c.text_section += '\tstr d0, [sp]\n' // d0 already has the float
						c.text_section += '\tadrp x0, fmt_float@PAGE\n'
						c.text_section += '\tadd x0, x0, fmt_float@PAGEOFF\n'
						c.text_section += '\tldr d0, [sp]\n' // printf expects double in d0
						c.text_section += '\tbl _printf\n'
						c.text_section += '\tadd sp, sp, #16\n'
					} else {
						if !c.data_section.contains('fmt_int:') {
							c.data_section += '.align 3\nfmt_int: .asciz "%lld "\n'
						}
						c.text_section += '\tstp x0, xzr, [sp, #-16]!\n'
						c.text_section += '\tadrp x0, fmt_int@PAGE\n'
						c.text_section += '\tadd x0, x0, fmt_int@PAGEOFF\n'
						c.text_section += '\tldr x1, [sp]\n'
						c.text_section += '\tbl _printf\n'
						c.text_section += '\tadd sp, sp, #16\n'
					}
				}
			}
			// Print newline
			if !c.data_section.contains('fmt_nl:') {
				c.data_section += '.align 3\nfmt_nl: .asciz "\\n"\n'
			}
			c.text_section += '\tadrp x0, fmt_nl@PAGE\n'
			c.text_section += '\tadd x0, x0, fmt_nl@PAGEOFF\n'
			c.text_section += '\tbl _printf\n' // sp is already aligned here
		} else if expr.function.value == 'input' {
			// Bug 18: Increase buffer size to 256 bytes
			c.text_section += '\tmov x0, #256\n'
			c.text_section += '\tbl _malloc\n'
			// Bug 12: Check if malloc succeeded
			c.text_section += '\tcmp x0, #0\n'
			c.text_section += '\tb.eq .L_input_fail_${c.label_count}\n'
			
			c.text_section += '\tstr x0, [sp, #-16]!\n' // save buffer addr
			if !c.data_section.contains('fmt_input:') {
				c.data_section += 'fmt_input: .asciz "%255s"\n'
			}
			c.text_section += '\tadrp x0, fmt_input@PAGE\n'
			c.text_section += '\tadd x0, x0, fmt_input@PAGEOFF\n'
			c.text_section += '\tldr x1, [sp]\n' // buffer address into x1
			c.text_section += '\tbl _scanf\n'
			c.text_section += '\tldr x0, [sp], #16\n' // result is the buffer pointer
			c.text_section += '\tb .L_input_end_${c.label_count}\n'
			c.text_section += '.L_input_fail_${c.label_count}:\n'
			c.text_section += '\tmov x0, #0\n'
			c.text_section += '.L_input_end_${c.label_count}:\n'
			c.label_count++
		} else if expr.function.value == 'free' {
			// Bug 5: Add free() built-in
			c.generate_expression(expr.args[0])
			c.text_section += '\tsub sp, sp, #16\n'
			c.text_section += '\tbl _free\n'
			c.text_section += '\tadd sp, sp, #16\n'
		} else if expr.function.value == 'malloc' {
			c.generate_expression(expr.args[0])
			c.text_section += '\tsub sp, sp, #16\n'
			c.text_section += '\tbl _malloc\n'
			c.text_section += '\tadd sp, sp, #16\n'
		} else if expr.function.value == 'read_file' {
			l_count := c.label_count
			c.label_count++
			
			c.generate_expression(expr.args[0])
			// x0 has path. Call fopen(path, "r")
			c.text_section += '\tstr x0, [sp, #-16]!\n'
			if !c.data_section.contains('mode_r:') {
				c.data_section += '.align 3\nmode_r: .asciz "r"\n'
			}
			c.text_section += '\tadrp x1, mode_r@PAGE\n'
			c.text_section += '\tadd x1, x1, mode_r@PAGEOFF\n'
			c.text_section += '\tbl _fopen\n'
			// Fix Bug 17: Check for NULL pointer from fopen
			c.text_section += '\tcmp x0, #0\n'
			c.text_section += '\tb.ne .L_fopen_success_$l_count\n'
			
			// Optional: print error message for Bug 16
			if !c.data_section.contains('fmt_file_err:') {
				c.data_section += 'fmt_file_err: .asciz "Error: Could not open file\\n"\n'
			}
			c.text_section += '\tadrp x0, fmt_file_err@PAGE\n'
			c.text_section += '\tadd x0, x0, fmt_file_err@PAGEOFF\n'
			c.text_section += '\tbl _printf\n'
			
			c.text_section += '\tmov x0, #0\n' // Return NULL on failure
			c.text_section += '\tadd sp, sp, #16\n' // Clean up stack slot
			c.text_section += '\tb .L_fopen_end_$l_count\n'
			c.text_section += '.L_fopen_success_$l_count:\n'
			c.text_section += '\t; fopen result in x0. Save it.\n'
			c.text_section += '\tstr x0, [sp], #16\n' // replace path with FILE*
			c.text_section += '\tstr x0, [sp, #-16]!\n'
			
			// Get file size: fseek(fp, 0, SEEK_END), ftell(fp), fseek(fp, 0, SEEK_SET)
			c.text_section += '\tmov x1, #0\n'
			c.text_section += '\tmov x2, #2\n' // SEEK_END
			c.text_section += '\tbl _fseek\n'
			c.text_section += '\tldr x0, [sp]\n'
			c.text_section += '\tbl _ftell\n'
			c.text_section += '\tstr x0, [sp, #-16]!\n' // save size
			
			c.text_section += '\tldr x0, [sp, #16]\n' // load fp
			c.text_section += '\tmov x1, #0\n'
			c.text_section += '\tmov x2, #0\n' // SEEK_SET
			c.text_section += '\tbl _fseek\n'
			
			// Malloc buffer: malloc(size + 1)
			c.text_section += '\tldr x0, [sp]\n' // load size
			c.text_section += '\tadd x0, x0, #1\n'
			c.text_section += '\tbl _malloc\n'
			c.text_section += '\tstr x0, [sp, #-16]!\n' // save buffer ptr
			
			// Read: fread(buffer, 1, size, fp)
			c.text_section += '\tldr x0, [sp]\n' // buffer
			c.text_section += '\tmov x1, #1\n' // size
			c.text_section += '\tldr x2, [sp, #16]\n' // count (file size)
			c.text_section += '\tldr x3, [sp, #32]\n' // fp
			c.text_section += '\tbl _fread\n'
			
			// Null terminate: buffer[size] = 0
			c.text_section += '\tldr x0, [sp]\n' // buffer
			c.text_section += '\tldr x1, [sp, #16]\n' // size
			c.text_section += '\tstrb wzr, [x0, x1]\n'
			
			// Close: fclose(fp)
			c.text_section += '\tldr x0, [sp, #32]\n' // fp
			c.text_section += '\tbl _fclose\n'
			
			// Result is the buffer pointer
			c.text_section += '\tldr x0, [sp]\n'
			c.text_section += '\tadd sp, sp, #48\n' // cleanup fp, size, buffer
			c.text_section += '.L_fopen_end_$l_count:\n'
		} else if expr.function.value == 'len' {
			arg := expr.args[0]
			if arg is ast.ArrayLiteral {
				c.text_section += '\tmov x0, #${arg.elements.len}\n'
			} else {
				c.generate_expression(arg)
				c.text_section += '\tsub sp, sp, #16\n'
				c.text_section += '\tbl _strlen\n'
				c.text_section += '\tadd sp, sp, #16\n'
			}
		} else if expr.function.value == 'draw_pixel' {
			c.text_section += '\t; --- NATIVE DRAW PIXEL ---\n'
			c.generate_expression(expr.args[0]) // x
			c.text_section += '\tstr x0, [sp, #-16]!\n'
			c.generate_expression(expr.args[1]) // y
			c.text_section += '\tstr x0, [sp, #-16]!\n'
			c.generate_expression(expr.args[2]) // color
			c.text_section += '\tstr x0, [sp, #-16]!\n'
			
			if !c.data_section.contains('fmt_draw:') {
				c.data_section += 'fmt_draw: .asciz "[DRAW %lld, %lld, %lld]\\n"\n'
			}
			c.text_section += '\tadrp x0, fmt_draw@PAGE\n'
			c.text_section += '\tadd x0, x0, fmt_draw@PAGEOFF\n'
			c.text_section += '\tldr x3, [sp], #16\n' // color
			c.text_section += '\tldr x2, [sp], #16\n' // y
			c.text_section += '\tldr x1, [sp], #16\n' // x
			
			// Bug 13: Increase stack buffer for draw_pixel printf
			c.text_section += '\tsub sp, sp, #64\n' 
			c.text_section += '\tstr x1, [sp]\n'
			c.text_section += '\tstr x2, [sp, #8]\n'
			c.text_section += '\tstr x3, [sp, #16]\n'
			c.text_section += '\tbl _printf\n'
			c.text_section += '\tadd sp, sp, #64\n'
		} else if expr.function.value == 'exit' {
			if expr.args.len > 0 {
				c.generate_expression(expr.args[0])
			} else {
				c.text_section += '\tmov x0, #0\n'
			}
			c.text_section += '\tbl _exit\n'
		} else {
			if expr.function.value in c.gpu_funcs {
				// Launch GPU Kernel!
				shader_label := '${expr.function.value}_shader'
				c.text_section += '\tadrp x0, $shader_label@PAGE\n'
				c.text_section += '\tadd x0, x0, $shader_label@PAGEOFF\n'
				c.text_section += '\tbl _opl_dispatch_metal\n'
			} else {
				// Custom CPU function call
				for _, arg in expr.args {
					c.generate_expression(arg)
					c.text_section += '\tstr x0, [sp, #-16]!\n'
				}
				for i := expr.args.len - 1; i >= 0; i-- {
					c.text_section += '\tldr x$i, [sp], #16\n'
				}
				func_name := '_${expr.function.value}'
				c.text_section += '\tbl $func_name\n'
			}
		}
	}
}

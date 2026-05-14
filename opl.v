module main

import os
import lexer
import parser
import codegen

fn main() {
	args := os.args
	if args.len < 2 {
		println('OPL Compiler (Built in V)')
		println('Usage: opl <command> [file]')
		println('Commands:')
		println('  build <file.opl>  - Compile OPL source file')
		println('  get <repo>        - OPM: Download package')
		println('  init              - OPM: Initialize module')
		return
	}

	command := args[1]
	
	if command == 'init' {
		os.write_file('opl.mod', 'module main\n') or { panic(err) }
		println('Initialized opl.mod')
		return
	} else if command == 'get' {
		if args.len < 3 {
			println('Usage: opl get <github-repo>')
			return
		}
		repo := args[2]
		// Security: only allow safe repo names (user/repo format)
		for ch in repo {
			if !ch.is_alnum() && ch != u8(`-`) && ch != u8(`_`) && ch != u8(`/`) && ch != u8(`.`) {
				println("Error: Invalid package name '${repo}'. Only letters, numbers, -, _, / and . are allowed.")
				return
			}
		}
		if repo.count('/') != 1 {
			println("Error: Package name must be in 'username/repo' format.")
			return
		}
		println("OPM: Fetching package ${repo}...")
		os.mkdir_all('./opl_modules') or { }
		res_clone := os.execute("git clone https://github.com/${repo} ./opl_modules/${repo}")
		if res_clone.exit_code == 0 {
			println("Package ${repo} installed successfully.")
		} else {
			println("Error: Failed to fetch package ${repo}.")
			println(res_clone.output)
		}
		return
	}
	
	if command == 'build' {
		if args.len < 3 {
			println('Error: Expected file path after "build"')
			return
		}
		filepath := args[2]
		
		if !os.exists(filepath) {
			println('Error: File "$filepath" not found.')
			return
		}
		
		source_code := os.read_file(filepath) or {
			println('Error: Could not read file "$filepath"')
			return
		}
		
		println('Compiling: $filepath')
		
		mut backend := 'asm' // ASM is now the default!
		mut target := 'native'
		
		if args.len > 3 {
			for i := 3; i < args.len; i++ {
				if args[i] == '--backend=c' {
					backend = 'c'
				} else if args[i] == '--backend=asm' {
					backend = 'asm'
				} else if args[i].starts_with('--target=') {
					target = args[i].replace('--target=', '')
				}
			}
		}
		
		// Auto-detect native target for ASM
		if target == 'native' {
			user_os := os.user_os()
			if user_os == 'macos' {
				target = 'arm64-macos'
			} else if user_os == 'linux' {
				target = 'x86_64-linux'
			} else if user_os == 'windows' {
				target = 'x86_64-windows'
			} else {
				println('Warning: Unknown OS ${user_os}. Falling back to C backend.')
				backend = 'c'
			}
		}

		// Lexer phase
		mut l := lexer.new(source_code)
		
		// Parser phase
		mut p := parser.new(mut l)
		program := p.parse_program()
		println('Parsed ${program.functions.len} functions.')
		
		// No longer need C fallback for loops, variables, threads!
		// ASM can do it ALL on ALL architectures!
		// GPU features are now transpiled to Metal/CUDA inline in ASM!
		
		if backend == 'asm' {
			println('Using ASM Backend for target: $target')
			mut asm_code := ''
			
			if target == 'arm64-macos' || target == 'native' {
				mut asm_gen := codegen.new_arm64_macos()
				asm_code = asm_gen.generate(program)
			} else if target == 'x86_64-linux' {
				mut asm_gen := codegen.new_x86_64_linux()
				asm_code = asm_gen.generate(program)
			} else if target == 'x86_64-windows' {
				mut asm_gen := codegen.new_x86_64_windows()
				asm_code = asm_gen.generate(program)
			} else {
				println('Error: Unsupported target $target')
				return
			}
			
			asm_filename := filepath.replace('.opl', '.s')
			os.write_file(asm_filename, asm_code) or { panic(err) }
			println('Generated ASM Code: $asm_filename')
			
			// Build with clang/gcc
			exe_name := filepath.replace('.opl', '')
			cmd := 'clang -o $exe_name $asm_filename'
			res := os.execute(cmd)
			if res.exit_code == 0 {
				println('Successfully built to executable: ./$exe_name')
				os.rm(asm_filename) or { } // Clean up intermediate .s file
			} else {
				println('ASM Compilation Error:\n$res.output')
			}
		} else {
			// C Backend
			mut c := codegen.new()
			c.compile(program)
			println('Generated C Code.')
			c.write_and_build(filepath)
		}
		
	} else {
		println('Unknown command: $command')
	}
}

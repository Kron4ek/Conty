// This is a bash-static initializer for Conty

#define _GNU_SOURCE

#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

// Replace all 0 below before compilation

// The size of our statically compiled bash binary
#define BASH_SIZE 0

// The size of conty-start.sh script
// It can be bigger than the actual size of the script
#define SCRIPT_SIZE 0

// The size of this program itself after compilation
// It can be bigger than the actual size of the program
#define PROGRAM_SIZE 0

// Bubblewrap can handle up to 9000 arguments
// And we reserve 1000 for internal use in Conty
#define MAX_ARGS_NUMBER 8000

int main(int argc, char* argv[])
{
	if (argc > MAX_ARGS_NUMBER) {
		printf("Too many arguments");
		return 1;
	}

	char program_path[8192] = { 0 };
	int binary_code[BASH_SIZE + 1];
	char bash_script[SCRIPT_SIZE + 1];

	readlink("/proc/self/exe", program_path, sizeof program_path);
	FILE *current_program = fopen(program_path, "rb");
	int bash_binary = memfd_create("bash-static", 0);

	fseek(current_program, PROGRAM_SIZE, 0);
	fread(binary_code, BASH_SIZE, 1, current_program);
	write(bash_binary, binary_code, BASH_SIZE);

	fseek(current_program, PROGRAM_SIZE + BASH_SIZE, 0);
	fread(bash_script, SCRIPT_SIZE, 1, current_program);
	fclose(current_program);

	char * bash_args[MAX_ARGS_NUMBER + 5] = {program_path, "-c", "--", bash_script, argv[0]};

	int k = 5;
	for (int i = 1; i < argc; i++, k++) {
		bash_args[k] = argv[i];
	}
	bash_args[k] = NULL;

	fexecve(bash_binary, bash_args, environ);
	printf("Failed to execute builtin bash-static");

    return 0;
}

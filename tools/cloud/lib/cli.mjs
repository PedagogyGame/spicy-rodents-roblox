// Minimal argv parsing: --flag value, --flag=value, --bool, positional args.
export function parseArgs(argv) {
	const flags = {};
	const positional = [];
	for (let i = 0; i < argv.length; i += 1) {
		const a = argv[i];
		if (a === "--") {
			positional.push(...argv.slice(i + 1));
			break;
		}
		if (a.startsWith("--")) {
			const eq = a.indexOf("=");
			if (eq !== -1) {
				flags[a.slice(2, eq)] = a.slice(eq + 1);
			} else if (i + 1 < argv.length && !argv[i + 1].startsWith("--")) {
				flags[a.slice(2)] = argv[i + 1];
				i += 1;
			} else {
				flags[a.slice(2)] = true;
			}
		} else {
			positional.push(a);
		}
	}
	return { flags, positional };
}

export function out(obj) {
	process.stdout.write(`${JSON.stringify(obj, null, 2)}\n`);
}

export function die(msg, code = 1) {
	process.stderr.write(`error: ${msg}\n`);
	process.exit(code);
}

export function fmtMs(ms) {
	return `${(ms / 1000).toFixed(1)}s`;
}

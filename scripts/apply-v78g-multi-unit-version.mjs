import fs from 'node:fs';
const path = 'src/FarmApp.tsx';
let source = fs.readFileSync(path, 'utf8');
if (source.includes('Perkebunan · v4.13.0')) process.exit(0);
if (!source.includes('Perkebunan · v4.12.2')) throw new Error('Version anchor v4.12.2 not found');
source = source.replace('Perkebunan · v4.12.2', 'Perkebunan · v4.13.0');
source += '\n/* v4.13 multi-unit inventory */\n';
fs.writeFileSync(path, source);

// One-time, non-overwriting import. Run with the SpacesOS path and --copy.
const fs = require('node:fs');
const path = require('node:path');
const source = path.resolve(process.argv[2]);
const destination = path.resolve(__dirname, '..');
function walk(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry =>
    entry.name.startsWith('.') || ['build', 'Downloads', 'reference', 'perf_results'].includes(entry.name) ? [] :
      entry.isDirectory() ? walk(path.join(directory, entry.name)) : [path.join(directory, entry.name)]);
}
const files = walk(source);
const texts = new Map(files.filter(file => file.endsWith('.gd')).map(file => [file, fs.readFileSync(file, 'utf8')]));
const classes = new Map([...texts].flatMap(([file, text]) => {
  const match = text.match(/^class_name (\w+)/m);
  return match ? [[match[1], file]] : [];
}));
const selected = new Set(files.filter(file => /^(foliage|lighting|atmosphere)[\\/]/.test(path.relative(source, file))));
// Imported assets and runtime data loaded through constructed paths.
for (const file of files) {
  if (/^(assets[\\/](foliage|audio|props|town)|content[\\/]furniture)[\\/]/.test(path.relative(source, file))) selected.add(file);
}
const missing = new Set();
for (const file of selected) {
  if (fs.existsSync(file + '.uid')) selected.add(file + '.uid');
  if (!/\.(gd|gdshader|gdshaderinc|tres|tscn|json)$/.test(file)) continue;
  const text = fs.readFileSync(file, 'utf8');
  if (file.endsWith('.gd')) {
    const code = text.split('\n').map(line => line.split('#')[0]).join('\n');
    for (const word of code.match(/\b\w+\b/g) || []) if (classes.has(word)) selected.add(classes.get(word));
  }
  for (const match of text.matchAll(/res:\/\/([^\s"')]+)/g)) {
    const dependency = path.join(source, match[1]);
    if (fs.existsSync(dependency) && fs.statSync(dependency).isFile()) selected.add(dependency);
    else if (!match[1].includes('%')) missing.add(match[1]);
  }
}
const paths = [...selected].sort();
console.log(`${paths.length} files, ${Math.round(paths.reduce((sum, file) => sum + fs.statSync(file).size, 0) / 1048576)} MiB`);
console.log('Support code:', paths.filter(file => file.endsWith('.gd') && !/^(foliage|lighting|atmosphere)[\\/]/.test(path.relative(source, file))).map(file => path.relative(source, file)).join('\n'));
console.log('Unresolved literal references (including documentation):', [...missing].join('\n'));
if (process.argv.includes('--copy')) {
  for (const file of paths) {
    const target = path.join(destination, path.relative(source, file));
    if (fs.existsSync(target)) throw new Error(`Refusing to overwrite ${target}`);
  }
  for (const file of paths) {
    const target = path.join(destination, path.relative(source, file));
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.copyFileSync(file, target);
  }
  fs.writeFileSync(path.join(destination, 'docs/spacesos-import.json'), JSON.stringify({source: 'SpacesOS', files: paths.map(file => path.relative(source, file).replaceAll('\\', '/'))}, null, 2) + '\n');
}


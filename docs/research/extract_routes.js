const fs = require('fs');
const text = fs.readFileSync('d:/Antigravity Companion/main.js', 'utf8');
const regex = /(?:'|\"|\`)\/(?:api|v1|v1beta|rpc)\/[a-zA-Z_/{}:-]+/g;
const matches = [...text.matchAll(regex)];
const unique = new Set(matches.map(m => m[0].slice(1)));
console.log([...unique].join('\n'));

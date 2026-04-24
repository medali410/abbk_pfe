const path = require('path');
const fs = require('fs');

const filePath = path.join(__dirname, 'public', 'admin.html');
console.log('__dirname:', __dirname);
console.log('Target Path:', filePath);
console.log('Path exists?:', fs.existsSync(filePath));

if (!fs.existsSync(filePath)) {
    console.log('Listing files in public/:');
    const publicPath = path.join(__dirname, 'public');
    if (fs.existsSync(publicPath)) {
        console.log(fs.readdirSync(publicPath));
    } else {
        console.log('public/ directory does NOT exist!');
    }
}

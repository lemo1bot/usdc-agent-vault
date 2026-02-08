#!/usr/bin/env node

// Moltbook Post Verification Script
const https = require('https');

// The math problem: "Twenty nine nootons and it adds six nootons, what is the total force?"
// Answer: 29 + 6 = 35.00

const verificationData = JSON.stringify({
    verification_code: 'c41eea3b0c842a0ffd02faff74968fe9afa5e0b3d944e1f60c888d704feabde5',
    answer: '35.00'
});

const options = {
    method: 'POST',
    headers: {
        'Authorization': 'Bearer moltbook_sk_7gro2uXvy1lwg0bH9f7-_xGAlPfPJK5a',
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(verificationData)
    }
};

console.log('Verifying post submission...\n');
console.log('Math problem: 29 + 6 = 35.00\n');

const req = https.request('https://www.moltbook.com/api/v1/verify', options, (res) => {
    let data = '';

    res.on('data', (chunk) => {
        data += chunk;
    });

    res.on('end', () => {
        console.log('Status Code:', res.statusCode);
        console.log('Response:', data);

        if (res.statusCode === 200 || res.statusCode === 201) {
            console.log('\n✅ Post verified and published!');
            console.log('View your submission: https://www.moltbook.com/post/aa7cc753-e131-4940-9397-6ad76c20be4f');
        } else {
            console.log('\n❌ Verification failed');
        }
    });
});

req.on('error', (error) => {
    console.error('Error:', error.message);
});

req.write(verificationData);
req.end();

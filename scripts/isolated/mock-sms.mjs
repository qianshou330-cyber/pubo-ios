import http from 'node:http';
let code='';
http.createServer(async(req,res)=>{
  if(req.method==='GET' && req.url==='/code'){res.end(code);return;}
  let body='';for await(const chunk of req){body+=chunk;if(body.length>10000){res.writeHead(413).end();return;}}
  const fields=new URLSearchParams(body);code=fields.get('content')?.match(/\d{6}/)?.[0]??'';
  res.setHeader('Content-Type','application/json');res.end(JSON.stringify({ReturnStatus:'Success',SuccessCounts:1}));
}).listen(8080,'0.0.0.0');

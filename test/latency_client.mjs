// Đo thật chi phí tính toán tái đánh giá phía client: haversine + point-in-polygon
// trên 25 sự kiện thật, cùng thuật toán với GeoLib.sol nhưng chạy bằng JS double.
import fs from 'fs';
const D = 'new URL('../data', import.meta.url).pathname';
const polys = JSON.parse(fs.readFileSync(`${D}/polygons.json`,'utf8'));
const rows  = fs.readFileSync(`${D}/events_raw.csv`,'utf8').trim().split('\n').slice(1)
  .map(l=>l.split(',')).map(c=>({lot:c[0],lat:+c[5],lon:+c[6]}))
  .filter(e=>e.lot==='BaSao'||e.lot==='NutriGreen');

const R=6371008, rad=d=>d*Math.PI/180;
const hav=(a,b)=>{const dp=rad(b.lat-a.lat)/2, dl=rad(b.lon-a.lon)/2;
  const x=Math.sin(dp)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dl)**2;
  return 2*R*Math.asin(Math.sqrt(x));};
const ring=v=>{const p=v.slice(); const f=p[0],l=p[p.length-1];
  if(f[0]===l[0]&&f[1]===l[1])p.pop(); return p.map(([lon,lat])=>({lat,lon}));};
function contains(q,poly){let c=false;
  for(let i=0,n=poly.length;i<n;i++){const a=poly[i],b=poly[(i+1)%n];
    if((a.lon>q.lon)!==(b.lon>q.lon)){
      const cr=(b.lat-a.lat)*(q.lon-a.lon)-(b.lon-a.lon)*(q.lat-a.lat);
      if(b.lon>a.lon?cr>0:cr<0)c=!c;}}
  return c;}
function distToSeg(q,a,b){const mLat=Math.PI*R/180, mLon=mLat*Math.cos(rad(q.lat));
  const ax=(a.lon-q.lon)*mLon, ay=(a.lat-q.lat)*mLat;
  const dx=(b.lon-q.lon)*mLon-ax, dy=(b.lat-q.lat)*mLat-ay;
  const dd=dx*dx+dy*dy; let t=dd===0?0:((-ax*dx-ay*dy)/dd);
  t=Math.max(0,Math.min(1,t));
  return hav(q,{lat:a.lat+(b.lat-a.lat)*t, lon:a.lon+(b.lon-a.lon)*t});}
function locate(q,poly){if(contains(q,poly))return 0;
  let best=Infinity; for(let i=0,n=poly.length;i<n;i++)
    best=Math.min(best,distToSeg(q,poly[i],poly[(i+1)%n])); return best;}

const P={BaSao:ring(polys.BaSao.vertices), NutriGreen:ring(polys.NutriGreen.vertices)};
const LENS=[[50,100],[30,80],[20,50]];
const pass=()=>{let acc=0;
  for(const e of rows){const d=locate(e,P[e.lot]);
    for(const [g,y] of LENS) acc += d<=g?0:(d<=y?1:2);}
  return acc;};

for(let i=0;i<200;i++) pass();               // warm-up JIT
const N=1000, t=[];
for(let i=0;i<N;i++){const s=process.hrtime.bigint(); pass();
  t.push(Number(process.hrtime.bigint()-s)/1e6);}
t.sort((a,b)=>a-b);
const mean=t.reduce((a,b)=>a+b)/N;
const sd=Math.sqrt(t.reduce((a,b)=>a+(b-mean)**2,0)/(N-1));
console.log(`su kien=${rows.length}  lens=3  lan lap=${N}`);
console.log(`toan bo 25 su kien x 3 lens : mean=${mean.toFixed(4)} ms  SD=${sd.toFixed(4)}  p50=${t[500].toFixed(4)}  p95=${t[950].toFixed(4)}`);
console.log(`quy ve moi su kien moi lens  : ${(mean/(rows.length*3)*1000).toFixed(2)} us`);
console.log(`node ${process.version}`);

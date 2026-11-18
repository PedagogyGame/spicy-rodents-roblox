// AER / 01 — SI units. JavaScript port of HockeyPhysics.h, shared model and rules.
class HockeyGame {
  constructor(){this.hitSerial=0;this.goalSerial=0;this.difficulty=1;this.reset()}
  reset(){this.score=[0,0];this.winner=-1;this.paused=false;this.serveSide=0;this.lastGoal=-1;this.paddles=[{p:[0,-.8],target:[0,-.8],v:[0,0]},{p:[0,.8],target:[0,.8],v:[0,0]}];this.resetPuck()}
  resetPuck(){this.puck=[0,this.serveSide?.3:-.3];this.velocity=[0,0];this.countdown=1.25}
  serve(){if(this.winner<0){this.countdown=0;this.velocity=[this.goalSerial%2?-.34:.34,this.serveSide?-1.25:1.25]}}
  setTarget(i,p){this.paddles[i].target=[clamp(p[0],-.556,.556),i?clamp(p[1],.064,1.106):clamp(p[1],-1.106,-.064)]}
  fold(x,b){let v=((x+b)%(4*b)+4*b)%(4*b);return v<=2*b?v-b:3*b-v}
  ai(i){let s=i?1:-1,m=this.paddles[i],p=this.puck,v=this.velocity,t=[p[0]*.65,s*.85];
    if(v[1]*s>.05){let dt=clamp((s*.88-p[1])/v[1],0,1.4);t=[this.fold(p[0]+v[0]*dt,.588),s*.88]}
    if(p[1]*s>.08&&p[1]*s<1.07){t=[p[0],p[1]+s*.115];if(Math.abs(m.p[0]-p[0])<.065&&(m.p[1]-p[1])*s>.025)t=[p[0]*.78,p[1]-s*.26]}
    if(this.countdown>0)t=[0,s*.8];this.setTarget(i,t)
  }
  toi(q,v,r,left){let a=dot(v,v),b=dot(q,v),c=dot(q,q)-r*r;if(c<=1e-10)return b< -1e-9?0:null;if(a<1e-12||b>=0)return null;let d=b*b-a*c;if(d<0)return null;let t=(-b-Math.sqrt(d))/a;return t>=-1e-9&&t<=left?t:null}
  tick(dt=1/240,human=0,computer=true){
    if(this.paused||this.winner>=0)return;if(computer)this.ai(1-human);
    let start=this.paddles.map(m=>m.p.slice());
    this.paddles.forEach((m,i)=>{m.v=mul(limit(sub(m.target,m.p),((i===human||!computer)?3.5:2.1*this.difficulty)*dt),1/dt)});
    if(this.countdown>0){this.paddles.forEach(m=>m.p=add(m.p,mul(m.v,dt)));this.countdown-=dt;if(this.countdown<=0)this.serve();return}
    this.velocity=mul(this.velocity,Math.exp(-.08*dt));let left=dt,elapsed=0;
    for(let k=0;k<16&&left>1e-9;k++){
      let hit={t:left+1,n:[0,0],surface:[0,0],kind:-1};
      let plane=(t,n,kind)=>{if(t>=-1e-9&&t<=left&&t<hit.t)hit={t:Math.max(0,t),n,surface:[0,0],kind}};
      for(let s of [-1,1]){
        if(this.velocity[0]*s>1e-9){plane((s*.588-this.puck[0])/this.velocity[0],[-s,0],0);let t=(s*.188-this.puck[0])/this.velocity[0];if(Math.abs(this.puck[1]+this.velocity[1]*t)>=1.17)plane(t,[-s,0],0)}
        if(this.velocity[1]*s>1e-9){let t=(s*1.138-this.puck[1])/this.velocity[1],x=this.puck[0]+this.velocity[0]*t;if(Math.abs(x)>=.22)plane(t,[0,-s],0);plane((s*1.277-this.puck[1])/this.velocity[1],[0,0],s>0?3:4)}
      }
      let circle=(c,v,r,kind)=>{let t=this.toi(sub(this.puck,c),sub(this.velocity,v),r,left);if(t!==null&&t<hit.t){let q=sub(add(this.puck,mul(this.velocity,t)),add(c,mul(v,t))),l=Math.hypot(...q);hit={t:Math.max(0,t),n:l>1e-9?mul(q,1/l):[0,1],surface:v,kind}}};
      for(let x of [-1,1])for(let y of [-1,1])circle([x*.22,y*1.17],[0,0],.044,0);
      this.paddles.forEach((m,i)=>circle(add(start[i],mul(m.v,elapsed)),m.v,.096,1));
      if(hit.kind<0){this.puck=add(this.puck,mul(this.velocity,left));left=0;break}
      this.puck=add(this.puck,mul(this.velocity,hit.t));elapsed+=hit.t;left-=hit.t;
      if(hit.kind===3||hit.kind===4){let scorer=hit.kind===3?0:1;this.score[scorer]++;this.lastGoal=scorer;this.goalSerial++;this.serveSide=1-scorer;if(this.score[scorer]>=7){this.winner=scorer;this.velocity=[0,0]}else this.resetPuck();break}
      let vn=dot(sub(this.velocity,hit.surface),hit.n);if(vn<0){this.velocity=add(this.velocity,mul(hit.n,-(1+(hit.kind===1?.94:.95))*vn));this.hitSerial++}
      this.velocity=limit(this.velocity,7.5);this.puck=add(this.puck,mul(hit.n,1e-6));if(hit.t<1e-8){let e=Math.min(left,1e-7);this.puck=add(this.puck,mul(this.velocity,e));left-=e;elapsed+=e}
    }
    this.paddles.forEach((m,i)=>m.p=add(start[i],mul(m.v,dt)))
  }
}
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
const add=(a,b)=>a.map((v,i)=>v+b[i]),sub=(a,b)=>a.map((v,i)=>v-b[i]),mul=(a,s)=>a.map(v=>v*s),dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
const limit=(a,m)=>{let n=Math.hypot(...a);return n>m?mul(a,m/n):a};

// Approved male key poses; source red is a runtime chroma key, never displayed.
// Same native frame contract and quota semantics as Reader. No network or audio.
(() => {
  if (!window.webkit?.messageHandlers?.pet) {
    const guide = document.getElementById('browser-guide');
    if (guide) guide.hidden = false;
    return;
  }
  const post = value => window.webkit.messageHandlers.pet.postMessage(value);
  const make = (w=256,h=256) => Object.assign(document.createElement('canvas'),{width:w,height:h});
  const target=make(), out=target.getContext('2d');
  let poses=[], expressions=[], revision=0;
  const key = canvas => {
    const ctx=canvas.getContext('2d'), pixels=ctx.getImageData(0,0,canvas.width,canvas.height), d=pixels.data;
    const mask=new Uint8Array(canvas.width*canvas.height), w=canvas.width,h=canvas.height;
    for(let n=0;n<mask.length;n++){
      const i=n*4,r=d[i],g=d[i+1],b=d[i+2];
      if(r>160 && r>g*2.4 && r>b*2.4){mask[n]=1;d[i+3]=0;}
    }
    // Decontaminate only the silhouette's one-pixel boundary, never skin/gold
    // inside the character. Global red-excess removal destroys warm skin.
    for(let y=1;y<h-1;y++)for(let x=1;x<w-1;x++){
      const n=y*w+x,i=n*4;if(mask[n])continue;
      const edge=mask[n-1]||mask[n+1]||mask[n-w]||mask[n+w];
      if(edge && d[i]>Math.max(d[i+1],d[i+2])*1.25){
        d[i]=Math.min(d[i],Math.max(d[i+1],d[i+2])*1.15);d[i+3]=210;
      }
    }
    ctx.putImageData(pixels,0,0);return canvas;
  };
  // Local book aperture segmentation. Only cyan/green inset pixels in this
  // asset-specific book ROI are recolored; gold rims and paper remain intact.
  function paintLamps(ctx,state,raised){
    const remaining=!state.loading && Number.isInteger(state.remaining) && state.remaining>=0 && state.remaining<=100 ? state.remaining : null;
    const pixels=ctx.getImageData(0,0,627,836),d=pixels.data;
    const groups=[[],[],[]], offset=raised ? -24 : 0;
    for(let y=345;y<442;y++)for(let x=428;x<482;x++){
      const i=(y*627+x)*4,r=d[i],g=d[i+1],b=d[i+2];
      if(d[i+3]>100 && g>r*1.08 && b>r*1.05 && g>55){
        const index=y<394+offset?0:y<415+offset?1:2;groups[index].push([i,y]);
      }
    }
    const color=remaining===null?[108,112,123]:remaining>=40?[48,209,88]:remaining>=20?[255,159,10]:[255,69,58];
    groups.forEach((group,index)=>{
      if(!group.length)return;
      const min=Math.min(...group.map(v=>v[1])),max=Math.max(...group.map(v=>v[1]));
      const amount=remaining===null?0:Math.max(0,Math.min(1,remaining*3/100-(2-index)));
      for(const [i,y] of group){
        const lit=amount>0 && y>=max-(max-min+1)*amount;
        const shade=0.65+0.35*Math.max(d[i],d[i+1],d[i+2])/255;
        const rgb=lit?color:[83,89,102];
        for(let c=0;c<3;c++)d[i+c]=Math.round(rgb[c]*shade);
      }
    });ctx.putImageData(pixels,0,0);
  }
  function rendered(index,state){
    const c=make(627,836), ctx=c.getContext('2d');ctx.drawImage(poses[index],0,0);
    paintLamps(ctx,state,index===2);
    const small=make();small.getContext('2d').drawImage(c,32,0,192,256);return small;
  }
  function mix(a,b,t){
    out.clearRect(0,0,256,256);out.globalCompositeOperation='lighter';
    out.globalAlpha=1-t;out.drawImage(a,0,0);out.globalAlpha=t;out.drawImage(b,0,0);
    out.globalAlpha=1;out.globalCompositeOperation='source-over';return target.toDataURL('image/png');
  }
  const poseIDs = new WeakMap(), pixels = new WeakMap(), fields = new Map();
  function flow(a,b) {
    const id=poseIDs.get(a)+'-'+poseIDs.get(b);
    if(fields.has(id))return fields.get(id);
    const encoded=window.archivistMotionFlow?.[id];
    if(!encoded)return null;
    const raw=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
    const view=new DataView(raw.buffer), small=new Float32Array(64*64*2);
    for(let i=0;i<small.length;i++)small[i]=view.getInt16(i*2,true)/256;
    const result=new Float32Array(256*256*2);
    for(let y=0;y<256;y++)for(let x=0;x<256;x++){
      const gx=Math.max(0,Math.min(63,(x+.5)/4-.5)),gy=Math.max(0,Math.min(63,(y+.5)/4-.5));
      const ix=Math.floor(gx),iy=Math.floor(gy),jx=Math.min(63,ix+1),jy=Math.min(63,iy+1),u=gx-ix,v=gy-iy;
      for(let k=0;k<2;k++)result[(y*256+x)*2+k]=small[(iy*64+ix)*2+k]*(1-u)*(1-v)+small[(iy*64+jx)*2+k]*u*(1-v)+small[(jy*64+ix)*2+k]*(1-u)*v+small[(jy*64+jx)*2+k]*u*v;
    }
    fields.set(id,result);return result;
  }
  function rgba(c){if(!pixels.has(c))pixels.set(c,c.getContext('2d').getImageData(0,0,256,256).data);return pixels.get(c);}
  function warpedMix(a,b,t){
    const f=flow(a,b),g=flow(b,a);
    if(!f||!g){
      if(poseIDs.has(a)&&poseIDs.has(b))throw new Error('Missing approved pose correspondence');
      return mix(a,b,t); // Eyelid-only blend, fixed body.
    }
    if(t===1)return b.toDataURL('image/png');
    const da=rgba(a),db=rgba(b),im=out.createImageData(256,256),d=im.data;
    // Bilinear sampling in premultiplied alpha prevents colored transparent fringes.
    function sample(src,x,y,c){
      if(x<0||y<0||x>255||y>255)return 0;
      const ix=Math.floor(x),iy=Math.floor(y),jx=Math.min(255,ix+1),jy=Math.min(255,iy+1),u=x-ix,v=y-iy;
      const at=(xx,yy)=>{const n=(yy*256+xx)*4;return src[n+c]*(c===3?1:src[n+3]/255);};
      return at(ix,iy)*(1-u)*(1-v)+at(jx,iy)*u*(1-v)+at(ix,jy)*(1-u)*v+at(jx,jy)*u*v;
    }
    for(let y=0;y<256;y++)for(let x=0;x<256;x++){
      const n=y*256+x,i=n*4,ax=x-t*f[n*2],ay=y-t*f[n*2+1],bx=x-(1-t)*g[n*2],by=y-(1-t)*g[n*2+1];
      const alpha=sample(da,ax,ay,3)*(1-t)+sample(db,bx,by,3)*t;d[i+3]=alpha;
      if(alpha>0)for(let c=0;c<3;c++)d[i+c]=(sample(da,ax,ay,c)*(1-t)+sample(db,bx,by,c)*t)*255/alpha;
    }
    out.putImageData(im,0,0);return target.toDataURL('image/png');
  }
  function transition(a,b,count){return Array.from({length:count*2},(_,i)=>{const t=(i+1)/(count*2);return warpedMix(a,b,t*t*(3-2*t));});}
  function expressive(index,state){
    const c=make(512,512),ctx=c.getContext('2d');ctx.drawImage(expressions[index],0,0);
    const pixels=ctx.getImageData(0,0,512,512),d=pixels.data,mask=new Set();
    for(let y=230;y<283;y++)for(let x=300;x<378;x++){
      const i=(y*512+x)*4,r=d[i],g=d[i+1],b=d[i+2];
      if(d[i+3]>100&&g>r*1.08&&b>r*1.05&&g>55)mask.add(y*512+x);
    }
    // Connected lamp faces remain distinct even when their slanted Y ranges overlap.
    const groups=[];
    while(mask.size){const seed=mask.values().next().value,group=[],todo=[seed];mask.delete(seed);
      while(todo.length){const n=todo.pop();group.push(n);for(const k of [n-1,n+1,n-512,n+512])if(mask.delete(k))todo.push(k);}
      if(group.length>12)groups.push(group);
    }
    const lamps=groups.sort((a,b)=>b.length-a.length).slice(0,3).sort((a,b)=>Math.min(...a)-Math.min(...b));
    const valid=!state.loading&&Number.isInteger(state.remaining)&&state.remaining>=0&&state.remaining<=100;
    const remaining=valid?state.remaining:null;
    const color=remaining===null?[83,89,102]:remaining>=40?[48,209,88]:remaining>=20?[255,159,10]:[255,69,58];
    lamps.forEach((lamp,n)=>{
      const ys=lamp.map(v=>Math.floor(v/512)),min=Math.min(...ys),max=Math.max(...ys);
      const amount=remaining===null||lamps.length!==3?0:Math.max(0,Math.min(1,remaining*3/100-(2-n)));
      for(const point of lamp){const i=point*4,y=Math.floor(point/512);
        const rgb=amount>0&&y>=max-(max-min+1)*amount?color:[83,89,102];
        const shade=.65+.35*Math.max(d[i],d[i+1],d[i+2])/255;
        for(let k=0;k<3;k++)d[i+k]=Math.round(rgb[k]*shade);
      }
    });ctx.putImageData(pixels,0,0);
    // Feet registration, not whole-silhouette centering (a head tilt shifts bounds).
    let minX=512,maxX=0,maxY=0;
    for(let y=430;y<512;y++)for(let x=0;x<512;x++)if(d[(y*512+x)*4+3]>200){minX=Math.min(minX,x);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
    const small=make();small.getContext('2d').drawImage(c,128-(minX+maxX)/2*250/512,247-maxY*250/512,250,250);return small;
  }
  window.setPetState=async state=>{
    const token=++revision;
    try{
      const acting=Array.from({length:6},(_,i)=>expressive(i,state));
      const [idle,page,tilt,tap,glance,smile]=acting;
      acting.forEach((pose,index)=>poseIDs.set(pose,index));
      const base=idle.toDataURL('image/png');
      const hold=(pose,count)=>Array(count*2).fill(pose.toDataURL('image/png'));
      const sequence=(stops,returnCount=10)=>{let from=idle,result=[];for(const [to,n,pause] of stops){result.push(...transition(from,to,n),...hold(to,pause));from=to;}result.push(...transition(from,idle,returnCount));return result;};
      // Existing closed-eye pose contributes only the eyelids, not a body dissolve.
      const closed=rendered(1,state),blink=make(),bc=blink.getContext('2d');bc.drawImage(idle,0,0);
      bc.drawImage(closed,103,70,54,12,103,76,54,12);
      const blinkFrames=[...transition(idle,blink,3),...hold(blink,3),...transition(blink,idle,4)];
      const hoverFrames=sequence([[glance,5,10],[smile,4,7]]);
      // Acknowledge, keep eye contact while the orbit settles, then return gently.
      // Counts are 30 Hz authoring units, baked at 60 Hz; 166 frames / 2.77 s.
      const turnFrames=sequence([[glance,7,8],[smile,6,16],[tap,10,12]],24);
      const readingVariants=[sequence([[page,7,14],[tap,6,12]]),sequence([[tilt,8,20],[page,6,8]]),sequence([[tap,6,16],[page,7,8]])];
      if(token!==revision)return;
      post({frame:base,frames:[base],blinkFrames,hoverFrames,turnFrames,readingFrames:readingVariants[0],readingVariants,state});
    }catch(error){post({error:String(error)});}
  };
  const image=new Image();
  image.onload=()=>{
    try{
      poses=[0,1,2].map(i=>{const c=make(627,836);c.getContext('2d').drawImage(image,i*image.width/3,0,image.width/3,image.height,0,0,627,836);const clean=key(c);if(i===2){const aligned=make(627,836);aligned.getContext("2d").drawImage(clean,35,0);return aligned;}return clean;});
      delete window.archivistPoseData;
      const sheet=new Image();sheet.onload=()=>{
        try { expressions=Array.from({length:6},(_,i)=>{
          const cell=make(512,512);cell.getContext('2d').drawImage(sheet,(i%3)*sheet.width/3,Math.floor(i/3)*sheet.height/2,sheet.width/3,sheet.height/2,0,0,512,512);
          return key(cell);
        });delete window.archivistExpressionData;post({ready:true}); }
        catch(error){post({error:String(error)});}
      };sheet.onerror=()=>post({error:'Expression asset failed to load'});sheet.src=window.archivistExpressionData;
    }catch(error){post({error:String(error)});}
  };
  image.onerror=()=>post({error:'Male sprite asset failed to load'});image.src=window.archivistPoseData;
})();

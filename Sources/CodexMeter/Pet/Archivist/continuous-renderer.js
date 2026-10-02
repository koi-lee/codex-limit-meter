// Same predecoded 30fps source-frame contract as Reader; no pose morphing.
(() => {
 if(!window.webkit?.messageHandlers?.pet){document.getElementById('browser-guide').hidden=false;return;}
 const post=body=>window.webkit.messageHandlers.pet.postMessage(body);
 const make=(size=256)=>Object.assign(document.createElement('canvas'),{width:size,height:size});
 let images=[],revision=0,loading;const masks=window.maleLampMasks;
 const snapshot=(n,state)=>{
  const c=make(384),ctx=c.getContext('2d');ctx.drawImage(images[n],0,0);
  const im=ctx.getImageData(0,0,384,384),d=im.data;
  const value=!state.loading&&Number.isInteger(state.remaining)&&state.remaining>=0&&state.remaining<=100?state.remaining:null;
  const color=value===null?[108,112,123]:value>=40?[48,209,88]:value>=20?[255,159,10]:[255,69,58];
  masks[n].forEach((group,band)=>{
   const ys=group.map(p=>Math.floor(p/384)),lo=Math.min(...ys),hi=Math.max(...ys);
   const amount=value===null?0:Math.max(0,Math.min(1,value*3/100-(2-band)));
   group.forEach((p,j)=>{const i=p*4,lit=amount>0&&ys[j]>=hi-(hi-lo+1)*amount,shade=.65+.35*Math.max(d[i],d[i+1],d[i+2])/255;
    const rgb=lit?color:[83,89,102];for(let k=0;k<3;k++)d[i+k]=Math.round(rgb[k]*shade);
   });
  });ctx.putImageData(im,0,0);
  const small=make();small.getContext('2d').drawImage(c,3,0,250,250);return small;
 };
 const blend=(a,b,count)=>Array.from({length:count},(_,i)=>{
  const c=make(),ctx=c.getContext('2d'),t=(i+1)/count,w=t*t*(3-2*t);
  ctx.globalCompositeOperation='lighter';ctx.globalAlpha=1-w;ctx.drawImage(a,0,0);ctx.globalAlpha=w;ctx.drawImage(b,0,0);return c.toDataURL('image/png');
 });
 window.setPetState=async state=>{
  const token=++revision;
  try {
   post({frame:snapshot(0,state).toDataURL('image/png'),state,preview:true});
   await loading;
   if(token!==revision)return;
   const canvases=images.map((_,n)=>snapshot(n,state));
   const frames=canvases.map(c=>c.toDataURL('image/png'));
   // Shorten the reading lead and long frontal hold; retain forward source order.
   const responseIndices=[
    ...Array.from({length:12},(_,i)=>i*2),
    ...Array.from({length:36},(_,i)=>24+i),
    ...Array.from({length:28},(_,i)=>60+Math.floor(i*1.5)),
    ...Array.from({length:48},(_,i)=>102+i)
   ];
   const turnFrames=[...responseIndices.map(i=>frames[i]),...blend(canvases[149],canvases[0],14)];
   const blinkFrames=[...frames.slice(0,28),...blend(canvases[27],canvases[0],6)];
   if(token!==revision)return;
   post({frame:frames[0],frames:[frames[0]],turnFrames,blinkFrames,hoverFrames:turnFrames,readingFrames:turnFrames,readingVariants:[turnFrames],state});
  }catch(e){post({error:String(e)});}
 };
 const loadImage=src=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(Error('Continuous frame load failed'));im.src=src;});
 loading=(async()=>{
  images[0]=await loadImage(window.maleContinuousFrames[0]);post({ready:true});
  const rest=await Promise.all(window.maleContinuousFrames.slice(1).map(loadImage));
  images=[images[0],...rest];delete window.maleContinuousFrames;
 })();
 loading.catch(e=>post({error:String(e)}));
})();

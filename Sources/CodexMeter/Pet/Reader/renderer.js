(() => {
  const post = body => window.webkit.messageHandlers.pet.postMessage(body);
  post({phase:'script-start'});
  const canvas = document.createElement('canvas'); canvas.width=400; canvas.height=600;
  const ctx = canvas.getContext('2d');
  const target=document.createElement('canvas'); target.width=256; target.height=256;
  const out=target.getContext('2d');
  let revision=0;
  let loading;
  const images=Array(150), bookImages=Array(150);
  const load=async()=>{
    images[0]=await new Promise((resolve,reject)=>{
      const image=new Image();image.onload=()=>resolve(image);image.onerror=()=>reject(Error('First frame failed'));image.src=window.readerFrameData[0];
    });
    post({ready:true});
    let next=1;
    await Promise.all(Array.from({length:6},async()=>{
      while(next<300){const n=next++;const destination=n<150?images:bookImages;destination[n%150]=await new Promise((resolve,reject)=>{
        const image=new Image();image.onload=()=>resolve(image);image.onerror=()=>reject(Error(`Frame ${n} failed`));
        image.src=n<150?window.readerFrameData[n]:window.bookLiftFrameData[n-150];
      });}
    }));
  };
  const frame=(n,book=false)=>{
    ctx.clearRect(0,0,400,600);ctx.drawImage((book?bookImages:images)[n],0,0);
    const originalMasks=window.readerLampMasks;
    try { if(book)window.readerLampMasks=window.bookLiftLampMasks;window.paintReaderLamps(ctx,n); }
    finally { window.readerLampMasks=originalMasks; }
    out.clearRect(0,0,256,256);out.drawImage(canvas,42.6667,0,170.6667,256);
    return target.toDataURL('image/png');
  };
  window.setPetState=async state=>{
    const token=++revision;
    try {
      post({phase:'state-render-start'});
      window.setReaderPetState(state);
      post({frame:frame(0),state,preview:true});
      await loading;
      if(token!==revision)return;
      const frames=[];
      for(let i=0;i<150;i++){
        if(token!==revision)return;
        frames.push(frame(i));

      }
      post({phase:'frames-rendered'});
      // Blend already-decoded canvases; reloading data URLs can stall in a hidden WKWebView.
      const snapshot=(n,book=false)=>{
        frame(n,book);const c=document.createElement('canvas');c.width=256;c.height=256;
        c.getContext('2d').drawImage(target,0,0);return c;
      };
      const ends=[snapshot(149),snapshot(0)];
      if(token!==revision)return;
      for(let i=1;i<=14;i++){
        const t=i/14,w=t*t*t*(t*(t*6-15)+10);
        out.clearRect(0,0,256,256);out.globalCompositeOperation='lighter';
        out.globalAlpha=1-w;out.drawImage(ends[0],0,0);
        out.globalAlpha=w;out.drawImage(ends[1],0,0);
        out.globalAlpha=1;out.globalCompositeOperation='source-over';
        frames.push(target.toDataURL('image/png'));
      }
      // Isolate the closed-eye beat before the source actor raises her head.
      const blend = async (a,b,count) => {
        const loaded=[a,b];
        const result=[];
        for(let i=1;i<=count;i++){
          const t=i/count,w=t*t*(3-2*t);
          out.clearRect(0,0,256,256);out.globalCompositeOperation='lighter';
          out.globalAlpha=1-w;out.drawImage(loaded[0],0,0);out.globalAlpha=w;out.drawImage(loaded[1],0,0);
          out.globalAlpha=1;out.globalCompositeOperation='source-over';result.push(target.toDataURL('image/png'));
        }
        return result;
      };
      const blinkFrames=[...await blend(ends[1],snapshot(29),3),...frames.slice(29,42),...await blend(snapshot(41),ends[1],5)];
      // Accepted single book-lift action; both transition endpoints already have quota overlays.
      const bookFrames=[];
      for(let i=0;i<150;i++)bookFrames.push(frame(i,true));
      const readingFrames=[...await blend(ends[1],snapshot(0,true),8),...bookFrames,
        ...await blend(snapshot(149,true),ends[1],12)];
      if(token!==revision)return;
      post({phase:"action-rendered"});
      const hoverFrames=[...frames.slice(0,65),...await blend(snapshot(64),ends[1],20)];
      const readingVariants=[readingFrames,[...await blend(ends[1],snapshot(0,true),8),...bookFrames.slice(0,90),...await blend(snapshot(89,true),ends[1],12)]];
      post({frame:frames[0],frames:[frames[0]],turnFrames:frames,blinkFrames,readingFrames,readingVariants,hoverFrames,state});
    } catch(error){post({error:String(error)});}
  };
  loading=load().then(()=>{delete window.readerFrameData;delete window.bookLiftFrameData;post({phase:'images-loaded'})}).catch(error=>post({error:String(error)}));
})();

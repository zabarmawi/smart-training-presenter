"""Build verified slide ranges for exact user fixtures, using saved local OCR evidence.
No original files are modified. Run from app after OCR and page-signature QA.
Number direction varies in the source slides; anchors below were checked against
actual Arabic headings, sequential session context and the previous timer data.
"""
from pathlib import Path
import json, re
catalog_path=Path('Resources/reference-catalog.json')
data=json.loads(catalog_path.read_text())
anchors={
 'enable-learning-2.1':[5,7,9,10,21,23,30,31,35,37,39,41,51,52,53,55,57,58,59,63,64,65,66,69,70,71,72,73,74,77,79,80,81],
 'enable-learning-2.2':[5,8,19,20,23,25,26,28,30,31,35,39,40,44,45,49,52,55,56,59,64,67,68,71,73,74,77,79,80],
}
breaks={
 'enable-learning-2.1':{'enable-learning-2.1-d1-s2-break0':29,'enable-learning-2.1-d1-external0':38,'enable-learning-2.1-d2-external0':67,'enable-learning-2.1-d2-external1':75},
 'enable-learning-2.2':{'enable-learning-2.2-d1-s2-unplaced0':24,'enable-learning-2.2-d1-s3-break0':36,'enable-learning-2.2-d2-external0':57,'enable-learning-2.2-d2-external1':69},
}
notes={
 'enable-learning-2.1-d1-s3-a1':'زمن المقدمة من المؤقت السابق. بداية الربط عنوان الجلسة الثالثة؛ الشريحة التالية تكرر عنوان نشاط سابق. راجع هذا النطاق قبل الاعتماد.',
 'enable-learning-2.1-d2-s4-a3':'المرجع يسمي التقييم 3-4-2، بينما الشريحة تكتب 2-4-4. طُوبق المحتوى «التقييم»؛ يلزم اعتمادك الصريح.',
 'enable-learning-2.2-d1-s2-unplaced0':'الشريحة تثبت موضع عرض الاستراحة، لكن جدول الزمن وموضعها في المؤقت السابق غير متفقين؛ راجع الترتيب والزمن يدويًا.',
}
# The image-only PowerPoint PDF cache preserves the exact PPTX order.
proof=[]
for package in data['packages']:
 pkg=package['id'];items=[a for d in package['days'] for s in d['sessions'] for a in s['activities']]
 starts=anchors[pkg];assert len(starts)==len(items)
 ppt_hash=next(h for h,f in data['fingerprints'].items() if f['packageID']==pkg and f['role']=='slides' and h in {
 '44a57c424ad9e88a769cc959962f3f0ac054ff1a492da0588b1daf273dacc15c',
 'c82b5ede9f7693c2dde38cd08338b004a12926d98041a12ece9cea353c94ac99'})
 n=82 if pkg.endswith('2.1') else 81
 links=[];break_pages=set(breaks[pkg].values())
 for ocr in Path('build/ocr-'+pkg.split('-')[-1]).glob('page-*.txt'):
  if 'استراحة' in ocr.read_text():break_pages.add(int(re.search(r'\d+',ocr.stem)[0]))
 for index,(a,start) in enumerate(zip(items,starts)):
  end=starts[index+1]-1 if index+1<len(starts) else n
  for page in sorted(break_pages):
   if start<page<=end:end=page-1;break
  entry={'activityID':a['id'],'start':start,'end':end}
  if a['id'] in notes:entry['note']=notes[a['id']]
  links.append(entry)
  ocr=Path('build/ocr-'+pkg.split('-')[-1])/f'page-{start}.txt'
  assert ocr.exists()
  text=ocr.read_text()
  proof.append({'activityID':a['id'],'officialCode':a['officialCode'],'referenceTitle':a['title'],'pptPage':start,'recognizedHeading':[l for l in text.splitlines() if 'نشاط' in l or 'الجلسة' in l or 'العودة' in l],'note':notes.get(a['id'])})
 for key,page in breaks[pkg].items():
  entry={'activityID':key,'start':page,'end':page}
  if key in notes:entry['note']=notes[key]
  links.append(entry)
 data['slideLinks'][ppt_hash]=links
 # Companion PDFs omit the copyright page. Pixel matching verifies every anchor
 # independently; no hardcoded page offset is trusted at import time.
 correspondence=json.loads(Path('build/page-correspondence.json').read_text())
 for pdf_hash,f in data['fingerprints'].items():
  if f['packageID']!=pkg or f['role']!='slides' or pdf_hash==ppt_hash:continue
  mapping=correspondence[pdf_hash]
  target=[]
  for link in links:
   a,b=str(link['start']),str(link['end'])
   assert mapping['errors'][a]<9, (pkg,a,mapping['errors'][a])
   assert mapping['errors'][b]<9, (pkg,b,mapping['errors'][b])
   translated=dict(link,start=mapping['pages'][a],end=mapping['pages'][b])
   target.append(translated)
  data['slideLinks'][pdf_hash]=target
catalog_path.write_text(json.dumps(data,ensure_ascii=False,indent=2))
Path('build/reference-link-evidence.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2))
print({h:len(v) for h,v in data['slideLinks'].items()})

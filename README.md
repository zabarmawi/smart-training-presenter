# Smart Training Presenter — مشغّل الحقائب التدريبية الذكي

إعداد: فهد عبدالله زبرماوي

حزم تجريبية للإصدار 0.6.1: Mac Intel وApple Silicon بالبناء 13، وWindows x64 بالبناء 15. اختلاف رقم البناء يعكس تاريخ بناء كل منصة؛ لا يعني تطابق حالة اختبارها.

## التنزيل السريع

اختر التطبيق المناسب لجهازك، ثم نزّل المكتبة المشتركة وأضفها مرة واحدة:

| الجهاز | التطبيق |
|---|---|
| Mac Intel | [تنزيل نسخة Intel](https://github.com/zabarmawi/smart-training-presenter/releases/download/v0.6.1-preview.1/SmartTrainingPresenter-0.6.1-B13-macOS-x86_64-preview.dmg) |
| Mac بمعالج M1 وما بعده | [تنزيل نسخة Apple Silicon](https://github.com/zabarmawi/smart-training-presenter/releases/download/v0.6.1-preview.1/SmartTrainingPresenter-0.6.1-B13-macOS-arm64-preview.dmg) |
| Windows x64 | [تنزيل مثبّت Windows](https://github.com/zabarmawi/smart-training-presenter/releases/download/v0.6.1-preview.1/SmartTrainingPresenter-0.6.1-B15-Windows-x64-Setup.exe) |

**[تنزيل المكتبة المشتركة — 11 حقيبة جاهزة](https://github.com/zabarmawi/smart-training-presenter/releases/download/v0.6.1-preview.1/SmartTrainingPresenter-TrainingLibrary-11Bags-v1.zip)**

[جميع التنزيلات وحدود الاختبار](https://github.com/zabarmawi/smart-training-presenter/releases/tag/v0.6.1-preview.1). هذه نسخة تجريبية؛ اقرأ المتطلبات والتعليمات أدناه.

## التثبيت والمكتبة

**المكتبة تُستعاد منفصلة؛ تثبيت التطبيق وحده على جهاز جديد لن يُظهر الحقائب تلقائيًا.**

لا يحتوي المصدر أو المثبّت وحدهما على الحقائب. تتوفر الآن حزمة مرافقة باسم SmartTrainingPresenter-TrainingLibrary-11Bags-v1.zip تضم 11 حقيبة جاهزة بالأزمنة والروابط والاعتمادات المسموح بتوزيعها من صاحب المشروع. نزّل حزمة المكتبة المرافقة أو انقل مكتبتك الخاصة من نسخة احتياطية موثوقة، واحتفظ بنسخة احتياطية من بيانات الجهاز الهدف قبل الاستعادة. لا تعِد استخراج الأنشطة لاستعادة القرارات المعتمدة.

- Windows: فك ZIP إلى مجلد مستقل أو استخدم المثبّت، ثم افتح «ملف ← استيراد المكتبة المعتمدة» واختر حزمة المكتبة الخاصة. يتطلب .NET Desktop Runtime 10 x64 مثبتًا مسبقًا؛ المثبّت لا يثبته تلقائيًا. عرض PDF يستخدم Windows.Data.Pdf المدمج في النظام. تحويل PowerPoint اختياري ويتطلب محولًا محليًا مناسبًا.
- Mac: اختر حزمة معالجك واسحب APP إلى Applications. توجد معلومات الإصدار والبناء و«إعداد: فهد عبدالله زبرماوي» في «الإعدادات ← حول التطبيق». لإضافة المكتبة المرافقة أغلق التطبيق ثم شغّل «إضافة المكتبة على Mac.command» الموجود داخل حزمة المكتبة. يرفض استبدال مكتبة موجودة. للتفاصيل راجع README داخل حزمة المكتبة وTools/README.md. لا تشغّل نسختين على بيانات المستخدم نفسها.

المكتبة المرافقة المصرح بتوزيعها تضم 11 حقيبة و341 اعتمادًا و769 إحالة، في ملف تنزيل مستقل؛ لا تتضمن ملف المستخدم الشخصي أو استعادة جلسته.

## العرض والمشاركة

شارك نافذة Shared Presentation وحدها في Teams. تبقى نافذة Trainer وأدوات التحكم خاصة. لا يوجد تكامل Teams مباشر، ولا خدمة هاتف أو خادم منشور. يعتمد العرض على الملفات المحلية؛ تحويل PowerPoint اختياري ويتطلب أدوات متوافقة مع الجهاز.

## حالة الاختبار

- Mac Intel Build 13 مشتق من المرجع Build 12، مع إضافة معلومات التطبيق. اختبرت واجهة «حول التطبيق» على Intel؛ تنقيح حزمة النشر أزال الكتالوج المرجعي الخاص دون تغيير الشيفرة التنفيذية، مع تجديد التوقيع.
- Apple Silicon Build 13: بناء ARM64 أصلي، ولم يُختبر التشغيل على جهاز Apple Silicon فعلي.
- Windows Build 15: توثق أدلة الجهاز المطور التثبيت والتشغيل المعتاد واستعادة المكتبة وتصحيح التصميم. بقيت تجربة جهاز مستقل وشاشتين فعليتين واستقبال Teams والسكون والسماع وتحويل PowerPoint، وقبول المستخدم النهائي.

حزم Mac موقعة محليًا ad-hoc وغير موثقة من Apple، وحزمة Windows غير موقعة. لا يزعم هذا الإصدار اكتمال القبول النهائي لجميع المنصات. راجع RELEASE-NOTES.md.

## المصدر والبناء

- macOS/: مصدر Swift مشترك للمعماريتين. من المجلد شغّل `PRESENTER_ARCH=x86_64 bash scripts/build.sh --dmg` أو `PRESENTER_ARCH=arm64 bash scripts/build.sh --dmg` على Mac مع أدوات تطوير Apple المناسبة.
- Windows/: مصدر Windows Forms. راجع README داخله؛ البناء يتم على Windows باستخدام .NET SDK 10 وأدوات Framework64.
- SharedContract/: نماذج واختبارات توافق وبيانات صناعية. فحص مستقل: `python3 SharedContract/conformance.py --self-test`.
- Tools/: أداة نقل مكتبة خاصة؛ لا تُضمّن بيانات المستخدم في المستودع.

لا يوجد ترخيص مفتوح المصدر مُعلن في هذه الحزمة؛ تجهيز المصدر للمراجعة لا يحدد رخصة إعادة توزيعه. لم يُضف ترخيص نيابة عن صاحب المشروع.

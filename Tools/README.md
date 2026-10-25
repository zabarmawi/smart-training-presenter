# إضافة المكتبة المرافقة ونقل البيانات

حزمة SmartTrainingPresenter-TrainingLibrary-11Bags-v1.zip مصرح بتوزيعها من صاحب المشروع وتضم 11 حقيبة معتمدة. محتواها منفصل عن المصدر ولا يتضمن استعادة جلسته أو تفضيلاته العامة.

في Windows استخدم «ملف ← استيراد المكتبة المعتمدة». في Mac أغلق التطبيق ثم افتح ملف «إضافة المكتبة على Mac.command» من الحزمة المرافقة. مصدر الأداة LibraryInstaller.swift هنا؛ الملفات التنفيذية متاحة في حزمة المكتبة للمعماريتين. تُرفض المكتبة الموجودة دون تعديلها.

للنقل التقني الاختياري باستخدام Python 3:

```sh
python3 portable_library.py verify /path/to/PORTABLE-APPROVED-LIBRARY
python3 portable_library.py restore /path/to/PORTABLE-APPROVED-LIBRARY /path/to/new-empty-destination
```

أمر restore وحده يستعيد الملفات ولا يفعّلها في واجهة Mac تلقائيًا؛ الأداة المرفقة تتولى الإضافة على تثبيت Mac جديد. لا تستبدل قرارات مستخدم أحدث. ملف المستخدم الشخصي ونسخ الجلسات يظلان خارج التوزيع.

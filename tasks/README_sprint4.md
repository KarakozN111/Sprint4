# Sprint 4 — Data Quality и сверки

## Цель
Научиться находить расхождения и защищать качество витрин.
---

1. Проверка дубликатов студентов по ИИН SQL-скрипт проверки:
```sql
select iin, count(*) as dublicate_count, array_agg(student_id) as student_ids
from raw.students
where iin is not null
group by iin
having count(*) > 1
order by dublicate_count desc;
```
###Отчёт по качеству: обнаружены кейсы, когда одному уникальному ИИН соответствует несколько разных student_id. Это технические дубликаты (один и тот же человек заведен в систему дважды).
###Влияние на витрины: при расчете аналитики (например, посещаемости или успеваемости) показатели ученика размываются по двум ID, искажая персональные отчеты.
###Предложение по исправлению: настроить ETL-процесс схлопывания дублей, либо выставить на уровне СУБД ограничение уникальности UNIQUE для колонки iin. Для существующих записей запустить процедуру дедупликации (слияния историй оценок на один мастер-ID).

2. Проверка оценок выше максимального балла SQL-скрипты проверки:
```sql
select student_id, subject_id, mark_type, mark, mark_max, (mark - mark_max) as overscore_by
from raw.student_marks
where mark> mark_max
order by overscore_by desc;

select student_id, subject_id, score, max_score, (score-max_score) as overescore_by
from raw.exam_results
where score> max_score
order by overescore_by desc;
```
###Отчёт по качеству: Обнаружены строки, где фактически выставленный балл (mark / score) превышает максимально допустимый лимит за работу (mark / max_mark), (exam_score / max_score ).
###Влияние на витрины: Метрика "Качество знаний (%)" и средний балл улетают выше 100%, ломая верхнеуровневые дашборды для Министерства/Управлений образования.
###Предложение по исправлению: Добавить проверку данных (Data Validation Constraint) на уровне фронтенда электронной системы, запрещающую вводить цифру больше max. В ETL-слое такие оценки временно приводить к максимальному лимиту (LEAST(mark, mark_max)).
3. Проверка отсутствующих связей (Referential Integrity) SQL-скрипт проверки:
```sql
select count(case when students.student_id is null then 1 end) as missing_students,
count(case when schools.school_id is null then 1 end)  as missing_schools,
count (case when subjects.subject_id is null then 1 end) as missing_subjects
from raw.student_marks

left join raw.students on student_marks.student_id=students.student_id
left join raw.schools on student_marks.school_id=schools.school_id
left join raw.subjects on student_marks.subject_id=subjects.subject_id;
```
###Отчёт по качеству: Найдено 835 строк с отсутствующими связями по предметам (missing_subjects). Это произошло из-за того, что в student_marks записаны некорректные ID предметов, которых нет в справочнике raw.subjects (где ID представлены строго от 1 до 9). Связи со школами и студентами нарушений не имеют.
###Влияние на витрины: При сборке финальной витрины через классический INNER JOIN эти 835 оценок просто исчезнут из отчетов (потому что для них нельзя подтянуть текстовое название предмета вроде «Математика»). Статистика школы окажется заниженной.
###Предложение по исправлению: Обновить справочник raw.subjects, добавив туда потерянные категории предметов, либо провести маппинг некорректных ID на дефолтное значение (например, ID = 99 с названием «Неизвестный предмет»)
4. Проверка удалённых оценок (Soft Delete) SQL-скрипт проверки:
```sql
select deleted_at, count(*) as count_marks, avg(mark) as avg_deleted_mark
from raw.student_marks
group by deleted_at;
```
###Отчёт по качеству: Система использует механизм "мягкого удаления" (Soft Delete). В базе зафиксировано 2 144 удаленных оценки (строки, где поле deleted_at заполнено датой и временем). Они распределены по 284 уникальным моментам времени (таймстемпам).
###Влияние на витрины: Если проигнорировать поле deleted_at, ошибочные оценки (двойки, опечатки), которые учителя уже отменили, попадут в расчет витрины. Это вызовет дублирование строк (две оценки за один СОР) и жестко занизит средние KPI классов.
###Предложение по исправлению: При сборке всех уровней витрин строго внедрить фильтрацию данных: WHERE deleted_at IS NULL.
5. Сверка слоев Source и Mart (Data Reconciliation) SQL-скрипт проверки:
```sql
select '1. RAW (Все сырые данные)' as layer, count(*) as layer
count(*) as total_marks_or_students
from raw.student_marks
union all
select '2. RAW (Очищенные данные - без удаленных)' as layer, count(*) as layer
count(*) as total_marks_or_students
from raw.student_marks
where deleted_at is null
union all
select '3. MART (Сумма по витрине)' as layer, sum(total_graded_students) as total_marks_or_students
from mart.mart_quality_of_knowledge;
```

##Результаты финальной сверки:
1. RAW (Все данные): 530 895 записей.
2. RAW (Очищенные): 528 751 запись (минус 2 144 удаленные строки).
3. MART (Витрина): 132 166 (в эквиваленте уникальных кейсов «Ученик-Предмет-Четверть»).

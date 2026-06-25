-- 1 проверить дубликаты студентов по иин
select iin, count(*) as dublicate_count, array_agg(student_id) as student_ids
from raw.students
where iin is not null
group by iin
having count(*) > 1
order by dublicate_count desc;

--2 оценки выше максимального балла
select student_id, subject_id, mark_type, mark, mark_max, (mark - mark_max) as overscore_by
from raw.student_marks
where mark> mark_max
order by overscore_by desc;

select student_id, subject_id, score, max_score, (score-max_score) as overescore_by
from raw.exam_results
where score> max_score
order by overescore_by desc;

--3 проверить отсутвующие связи по студентам, школам и предметам
select count(case when students.student_id is null then 1 end) as missing_students,
count(case when schools.school_id is null then 1 end)  as missing_schools,
count (case when subjects.subject_id is null then 1 end) as missing_subjects
from raw.student_marks

left join raw.students on student_marks.student_id=students.student_id
left join raw.schools on student_marks.school_id=schools.school_id
left join raw.subjects on student_marks.subject_id=subjects.subject_id;

--4 Проверить удалённые оценки и их влияние на витрины.
select deleted_at, count(*) as count_marks, avg(mark) as avg_deleted_mark
from raw.student_marks
group by deleted_at;

--5 сверка source и mart по количеству оценок и студентов
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









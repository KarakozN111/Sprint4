-- 3 построить список школ по регионам и районам
select raw.regions.region_name as регион,
       raw.departments.department_name as район_отдел_образования,
       raw.schools.school_id as id_школы,
       raw.schools.school_name as название_школы,
       -- дополнительно
       raw.schools.school_type as тип_школы,
       raw.schools.locality_type as тип_местности,
       raw.schools.education_lang as язык_обучения
from raw.schools

join raw.departments on raw.schools.department_id = raw.departments.department_id
join raw.regions on raw.departments.region_id = raw.regions.region_id
order by raw.regions.region_name, raw.departments.department_name, raw.schools.school_name;


-- 4 посчитать количество учеников по региону, школе и классу
select raw.regions.region_name as регион,
       raw.schools.school_name as название_школы,
       -- склеиваем цифру и букву класса
       raw.groups.grade || ' ' || raw.groups.letter as класс,
       count (raw.students.student_id) as количество_учеников
from raw.students

join raw.groups on raw.students.group_id= raw.groups.group_id
join raw.schools on raw.students.school_id= raw.schools.school_id
join raw.departments on raw.schools.department_id= raw.departments.department_id
join raw.regions on raw.departments.region_id=raw.regions.region_id

group by raw.regions.region_name, raw.schools.school_name, raw.groups.grade, raw.groups.letter

order by raw.regions.region_name, raw.schools.school_name, raw.groups.grade, raw.groups.letter;


-- 5 средний балл по предметам и школам
select raw.subjects.subject_name as предмет,
       raw.regions.region_name as регион,
       raw.schools.school_name as название_школы,
       round(avg(raw.student_marks.mark), 2) as средний_балл
from raw.student_marks

join raw.students on student_marks.student_id= raw.students.student_id
join raw.groups on raw.students.group_id= raw.groups.group_id
join raw.schools on raw.groups.school_id=raw.schools.school_id
join raw.departments on raw.schools.department_id= raw.departments.department_id
join raw.regions on raw.departments.region_id=raw.regions.region_id
join raw.subjects on raw.student_marks.subject_id= raw.subjects.subject_id

group by raw.subjects.subject_name, raw.regions.region_name, raw.schools.school_name

order by raw.subjects.subject_name, raw.regions.region_name, raw.schools.school_name;


-- Процент ошибок в датасете

select email, 'hash_password' as hashed_password, now() as confirmed_at, 
       now() as inserted_at, now() as updated_at
  from users

select u.email, n.name as nutrient_name, n.unit, 
       n.created_at as inserted_at, n.updated_at as updated_at 
  from nutrients n inner join users u on u.id = n.user_id

select u.email, i.name as ingredient_name, i.cost, i.category, 1 as dry_matter, i.note as description, 
       i.created_at as inserted_at, i.updated_at as updated_at 
  from ingredients i inner join users u on u.id = i.user_id 

select u.email, i.name as ingredient_name, n.name as nutrient_name, ic.value as quantity
  from ingredient_compositions ic inner join ingredients i 
    on i.id = ic.ingredient_id inner join nutrients n 
    on n.id = ic.nutrient_id inner join users u 
    on u.id = i.user_id 

select u.email, f.name as formula, f.batch_size, u.weight_unit, f.usage_per_day, f.note, 
	   f.target_bag_weight as premix_bag_weight, f.usage_bags as premix_bag_usage_qty,
	   f.bags_of_premix as premix_bags_qty,
       f.created_at as inserted_at, f.updated_at as updated_at 
from formulas f inner join users u 
  on u.id = f.user_id 

select u.email, f."name" as formula_name, i.name as ingredient_name, i."cost", 
       fi.min , fi.max , fi.actual , fi.weight , fi.shadow , fi.use as used
  from formulas f inner join users u 
  	on u.id = f.user_id inner join formula_ingredients fi 
  	on fi.formula_id = f.id  inner join ingredients i 
  	on i.id = fi.ingredient_id

select u.email, f."name" as formula_name, n.name as nutrient_name, 
       fn.min , fn.max , fn.actual, fn.use as used
  from formulas f inner join users u 
  	on u.id = f.user_id inner join formula_nutrients fn 
  	on fn.formula_id = f.id  inner join nutrients n 
  	on n.id = fn.nutrient_id 

select u.email, f."name" as formula_name, i.name as ingredient_name, 
       fi.actual_usage as formula_quantity, fi.premix_usage as premix_quantity
  from formulas f inner join users u 
  	on u.id = f.user_id inner join premix_ingredients fi 
  	on fi.formula_id = f.id  inner join ingredients i 
  	on i.id = fi.ingredient_id



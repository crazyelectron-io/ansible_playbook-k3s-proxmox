// file: conf/transform/array.js
// synopsis: Transforms a string to a single element

(function(i,j) {
  var item = parseInt(j);   // array index as int
  var fixed = i.slice(1,i.length-1);   // remove brackets from incoming string
  var list = fixed.split(",");    // turn string into an array
  var price = parseFloat(list[item]);   // select the requested item as float
  return price;   // return the float number
})(input, item)

/**
 * Splits into groups of 3 characters
*/
function formatId(id) {
    return id.split("").reverse().join("")  // Reverse the string
             .match(/.{1,3}/g)              // Group into sets of 3
             .join(" ")                      // Join groups with thin spaces
             .split("").reverse().join("");  // Reverse back
}
/**
 * Splits into groups of 3 characters
 */
function formatId(id) {
    return id.split("").reverse().join("")  // Reverse the string
             .match(/.{1,3}/g)              // Group into sets of 3
             .join(" ")                      // Join groups with thin spaces
             .split("").reverse().join("");  // Reverse back
}

/**
 * Loop through menus and hide each one
 */
function closeAllMenus() {
    const menuElements = document.querySelectorAll('[id$="-menu"]');
    menuElements.forEach(element => {
        element.style.display = 'none';
    });
}


/** 
 * Handle 'Delete' button when sub-menu opened
 */
document.onkeyup = function (data) {
    console.log(data);
    if (isSpoonerHudOpened && (data.code == 'Delete')) {
        fetch(`https://${GetParentResourceName()}/close`,{
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8',
            },
            body: JSON.stringify({})
        });
    }
};
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

function formatNumber(num) {
    return Number(num).toLocaleString('en', {useGrouping: false, minimumFractionDigits: 1});
}

///////////////////
// Player Bucket //
///////////////////
let playerRoutingBucket = 0;
window.addEventListener('message', function(event) {
	switch (event.data.type) {
        case 'onRequestPlayerRoutingBucket':
            playerRoutingBucket = event.data.bucket;
            document.getElementById('routing-bucket').innerHTML = playerRoutingBucket;
            break;
    }
});
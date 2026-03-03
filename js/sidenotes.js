// Sidenote toggle functionality for mobile/narrow screens
// Add numbers to sidenotes and their references
(function() {
    var wrappers = document.querySelectorAll('.sidenote-wrapper');
    
    for (var i = 0; i < wrappers.length; i++) {
        (function(wrapper) {
            var checkbox = wrapper.querySelector('.margin-toggle[type="checkbox"]');
            var sidenote = wrapper.querySelector('.sidenote');
            var label = wrapper.querySelector('label.margin-toggle.sidenote-number');
            
            if (checkbox && label) {
                var id = checkbox.id;
                var num = id.replace('sn-', '');
                
                // Add number to the label (superscript in main text)
                label.textContent = num;
                
                // Add number to sidenote content
                if (sidenote) {
                    var numberSpan = document.createElement('span');
                    numberSpan.className = 'sidenote-number';
                    numberSpan.textContent = num + '. ';
                    sidenote.insertBefore(numberSpan, sidenote.firstChild);
                }
            }
        })(wrappers[i]);
    }

    // Toggle functionality for mobile
    var checkboxes = document.querySelectorAll('.margin-toggle');
    
    for (var j = 0; j < checkboxes.length; j++) {
        (function(checkbox) {
            checkbox.addEventListener('click', function() {
                var sidenote = this.parentElement.querySelector('.sidenote');
                if (sidenote) {
                    if (this.checked) {
                        sidenote.style.display = 'block';
                    } else {
                        sidenote.style.display = 'none';
                    }
                }
            });
        })(checkboxes[j]);
    }
})();

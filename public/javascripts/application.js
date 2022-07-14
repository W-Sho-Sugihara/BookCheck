$(function () {
  $("form.delete").submit(function (event) {
    event.preventDefault();
    event.stopPropagation();

    var ok = confirm("Deleting this cannot be undone! Continue to delete?");
    if (ok) {
      this.submit();
    }
  });
});

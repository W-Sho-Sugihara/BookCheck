$(function () {
  $("form.delete").submit(function (event) {
    event.preventDefault();
    event.stopPropagation();

    var ok = confirm(
      "Deleting an account cannot be undone! Continue to delete?"
    );
    if (ok) {
      this.submit();
    }
  });
});

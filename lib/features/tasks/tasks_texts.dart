/// The words of the Tasks feature, in one place.
class TasksTexts {
  TasksTexts._();

  static const screenTitle = 'Tasks';
  static const tabAssigned = 'Assigned to me';
  static const tabCreated = 'Created by me';
  static const filterActive = 'Active';
  static const filterDone = 'Done';
  static const filterCancelled = 'Cancelled';
  static const filterAll = 'All';
  static const newTask = 'New task';
  static const retry = 'Retry';

  static const emptyAssignedTitle = 'No tasks for you';
  static const emptyCreatedTitle = 'No tasks created';
  static const emptyAssignedMessage = 'Tasks given to you show up here.';
  static const emptyCreatedMessage = 'Tasks you give to people show up here.';
  static const emptyFilteredMessage = 'Nothing matches this filter.';
  static const errorMessage = "Couldn't load your tasks.";

  static const fromLabel = 'From';
  static const forLabel = 'For';
  static const me = 'Me';
  static const you = 'You';
  static const overdue = 'Overdue';
  static const noDue = 'No due date';
  static const today = 'Today';
  static const tomorrow = 'Tomorrow';

  static const detailTitle = 'Task';
  static const createdBy = 'Created by';
  static const assignedTo = 'Assigned to';
  static const due = 'Due';
  static const priority = 'Priority';
  static const status = 'Status';
  static const description = 'Description';
  static const noDescription = 'No description.';

  static const start = 'Start';
  static const markDone = 'Mark done';
  static const reopen = 'Reopen';
  static const edit = 'Edit';
  static const cancelTask = 'Cancel task';
  static const sendToSomeone = 'Send to someone else';

  static const formCreateTitle = 'New task';
  static const formEditTitle = 'Edit task';
  static const fieldTitle = 'Title';
  static const fieldTitleHint = 'What needs doing?';
  static const fieldDescription = 'Description';
  static const fieldDescriptionHint = 'Add details (optional)';
  static const fieldDue = 'Due date';
  static const fieldDueHint = 'No due date';
  static const fieldPriority = 'Priority';
  static const fieldAssignee = 'Assign to';
  static const clearDue = 'Clear due date';
  static const create = 'Create task';
  static const save = 'Save changes';

  static const pickerTitle = 'Assign to';
  static const pickerSearch = 'Search people';
  static const pickerEmpty = 'No people found.';
  static const pickerError = "Couldn't load people.";
  static const sendTitle = 'Send to';

  static const titleRequired = 'Add a title.';
  static const titleTooLong = 'The title can be at most 120 characters.';
  static const descriptionTooLong =
      'The description can be at most 2000 characters.';
  static const duePast = 'Pick today or a later date.';

  static const newTaskNotice = 'You have a new task.';
  static const updatedNotice = 'A task was updated.';
  static const createdDone = 'Task created.';
  static const savedDone = 'Changes saved.';
  static const sentDone = 'Task sent.';

  static String priorityLabel(String p) => switch (p) {
    'low' => 'Low',
    'high' => 'High',
    _ => 'Normal',
  };

  static String statusLabel(String s) => switch (s) {
    'in_progress' => 'In progress',
    'done' => 'Done',
    'cancelled' => 'Cancelled',
    _ => 'Open',
  };
}

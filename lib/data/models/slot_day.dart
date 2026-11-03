/// A day of times to book, from `avail.slots`.
class SlotDay {
  const SlotDay(this.date, this.times);

  final String date;
  final List<SlotTime> times;
}

class SlotTime {
  const SlotTime(this.time, this.isFree);

  final String time;
  final bool isFree;
}

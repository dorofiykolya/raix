package rx.tests.mocks
{
	import rx.scheduling.IScheduledAction;
	import rx.scheduling.IScheduler;

	public class NullScheduler implements IScheduler
	{
		public function schedule(action:Function, dueTime:int=0):IScheduledAction
		{
			return new NullScheduledAction();
		}
		
		private var _now : Date = new Date();
		
		public function get now() : Date { return _now; }
		public function set now(value : Date) : void { _now = value; }
		
	}
}
package rx
{
	import flash.display.LoaderInfo;
	import flash.errors.IllegalOperationError;
	import flash.events.*;
	import flash.utils.Timer;
	
	import rx.impl.*;
	import rx.scheduling.*;

	public class Observable
	{
		public function Observable()
		{
			throw new IllegalOperationError("This class is static and cannot be instantiated. Create an IObservable by using one of Observable's static methods");
		}
		
		public static function amb(sources : Array/*.<IObservable>*/) : IObservable
		{
			sources = new Array().concat(sources);
			
			return new ClosureObservable(int, function(observer : IObserver) : ISubscription
			{
				var subscription : CompositeSubscription = new CompositeSubscription([])
			
				for each(var source : IObservable in sources)
				{
					(function(obs:IObservable):void
					{
						var futureSubscription : FutureSubscription = new FutureSubscription();
						subscription.add(futureSubscription);
					
						futureSubscription.innerSubscription = obs.subscribeFunc(
							function(pl:Object) : void
							{
								var newSubscriptions : CompositeSubscription = 
									new CompositeSubscription(subscription.subscriptions);
									
								newSubscriptions.remove(futureSubscription);
								newSubscriptions.unsubscribe();
								
								observer.onNext(pl);
							},
							function():void { observer.onCompleted(); },
							function(e:Error):void { observer.onError(e); }
							);
					})(source);
				}
				
				return subscription;
			});
		}
		
		public static function defer(type : Class, observableFactory:Function):IObservable
		{
			if (observableFactory == null)
			{
				throw new ArgumentError("observableFactory cannot be null");
			}
			
			return new ClosureObservable(type, function(observer : IObserver):ISubscription
			{
				var observable : IObservable = observableFactory();
				
				if (observable.type != type)
				{
					throw new ArgumentError("Deffered observable type must match type given to defer"); 
				}
				
				return observable.subscribe(observer);
			});
		}
		
		public static function interval(intervalMs : uint, scheduler : IScheduler = null):IObservable
		{
			scheduler = Observable.resolveScheduler(scheduler);
			
			return new ClosureObservable(int, function(observer : IObserver) : ISubscription
			{
				var intervalIndex : uint = 0;
				
				var scheduledAction : IScheduledAction = null;
				
				var recursiveAction : Function;
				recursiveAction = function():void
				{
					observer.onNext(++intervalIndex);
					
					scheduledAction = scheduler.schedule(recursiveAction, intervalMs);
				};
				
				scheduledAction = scheduler.schedule(recursiveAction, intervalMs);
				
				return new ClosureSubscription(function():void
				{
					scheduledAction.cancel();
				});
			});
		}
		
		public static function fromEvent(eventDispatcher:IEventDispatcher, type:String, eventType : Class = null, useCapture:Boolean=false, priority:int=0):IObservable
		{
			eventType = eventType || Event;
			
			if (eventDispatcher == null)
			{
				throw new ArgumentError("eventDispatcher cannot be null");
			}
			
			return new ClosureObservable(eventType, function(observer : IObserver, scheduler : IScheduler = null) : ISubscription
			{
				scheduler = Observable.resolveScheduler(scheduler);
				
				var listener : Function = function(event : Event) : void
				{
					scheduler.schedule(function():void
					{
						observer.onNext(event);
					});
				};
				
				scheduler.schedule(function():void
				{
					eventDispatcher.addEventListener(type, listener, useCapture, priority);
				});
				
				return new ClosureSubscription(function():void
				{
					eventDispatcher.removeEventListener(type, listener, useCapture);
				});
			});
		}
		
		public static function empty(observableType : Class = null, scheduler : IScheduler = null) : IObservable
		{
			observableType = observableType || Object;
			scheduler = scheduler || ImmediateScheduler.instance;
			
			return new ClosureObservable(observableType, function(obs:IObserver) : ISubscription
			{
				return new ScheduledActionSubscription(
					scheduler.schedule(obs.onCompleted)
				);
			});
		}
		
		public static function onErrorResumeNext(sources:Array, scheduler:IScheduler=null):IObservable
		{
			if (sources == null || sources.length == 0)
			{
				throw new ArgumentError("sources");
			}
			
			scheduler = resolveScheduler(scheduler);
			
			// Make internally immutable
			sources = new Array().concat(sources);
			
			return new ClosureObservable(sources[0].type, function(obs:IObserver) : ISubscription
			{
				var remainingSources : Array = new Array().concat(sources);
				
				var subscription : ISubscription = null;
				var futureSubscription : FutureSubscription = new FutureSubscription();
				
				var scheduledAction : IScheduledAction = null;
				
				var moveNextFunc : Function = null;
				
				moveNextFunc = function():void
				{
					var currentSource : IObservable = remainingSources.shift();
					
					if (subscription != null)
					{
						subscription.unsubscribe();
					}
					
					subscription = currentSource.subscribeFunc(
						function(pl:Object) : void { obs.onNext(pl); },
						function() : void
						{
							if (remainingSources.length > 0)
							{
								scheduledAction = scheduler.schedule(moveNextFunc);
							}
							else
							{
								obs.onCompleted();
							}
						},
						function(e:Error) : void
						{
							if (remainingSources.length > 0)
							{
								scheduledAction = scheduler.schedule(moveNextFunc);
							}
							else
							{
								obs.onError(e);
							}
						});
					
					futureSubscription.innerSubscription = subscription;
				};
				
				scheduledAction = scheduler.schedule(moveNextFunc);
				
				return new ClosureSubscription(function():void
				{
					if (scheduledAction != null)
					{
						scheduledAction.cancel();
					}
					
					if (futureSubscription != null)
					{
						futureSubscription.unsubscribe();
					}
				});
			});
		}
		
		/**
		 * Returns an IObservable that never completes
		 */		
		public static function never(observableType : Class = null) : IObservable
		{
			observableType = observableType || Object;
			
			return new ClosureObservable(observableType, function(obs:IObserver) : ISubscription
			{
				return new ClosureSubscription(function():void{});
			});
		}
		
		public static function uncaughtErrors(loaderInfo : LoaderInfo = null) : IObservable
		{
			loaderInfo = loaderInfo || LoaderInfo.getLoaderInfoByDefinition(Observable);
			
			var uncaughtErrorsSupported : Boolean = 
				loaderInfo.hasOwnProperty("uncaughtErrorEvents");
			
			if (uncaughtErrorsSupported)
			{
				return fromEvent(
					IEventDispatcher(loaderInfo["uncaughtErrorEvents"]),
					"uncaughtError"
					);
			}
			else
			{
				return never();
			}
		}
		
		public static function range(start : int, count : uint, scheduler : IScheduler = null) : IObservable
		{
			scheduler = Observable.resolveScheduler(scheduler);
			
			return new ClosureObservable(int, function(obs:IObserver) : ISubscription
			{
				var end : int = start + count;
				
				var scheduledActions : Array = new Array();
				
				var scheduledAction : IScheduledAction = null;
				
				var i : int = start;
				
				var rescursiveAction : Function = null;
				
				rescursiveAction = function():void
				{
					obs.onNext(i);
					
					i++;
					
					if (i < end)
					{
						scheduledAction = scheduler.schedule(rescursiveAction);
					}
					else
					{
						obs.onCompleted();
					}
				};
				
				scheduledAction = scheduler.schedule(rescursiveAction);

				return new ClosureSubscription(function():void
				{
					scheduledAction.cancel();
				});
			});
		}		
		
		public static function throwError(error : Error, observableType : Class = null) : IObservable
		{
			if (error == null)
			{
				throw new ArgumentError("error cannot be null");
			}
			
			observableType = observableType || Object;
			
			return new ClosureObservable(observableType, function(obs:IObserver) : ISubscription
			{
				obs.onError(error);
				
				return new ClosureSubscription(function():void{});
			});
		}
		
		public static function returnValues(type : Class, values : Array, scheduler : IScheduler = null) : IObservable
		{
			scheduler = resolveScheduler(scheduler);
			
			return new ClosureObservable(type, function(obs:IObserver) : ISubscription
			{
				var valueScheduledAction : IScheduledAction = null;
				
				for each(var value : Object in values) 
				{
					(function(value:Object) : void
					{
						valueScheduledAction = 
							scheduler.schedule(function():void { obs.onNext(value); });
					})(value);
				}
				
				var completeScheduledAction : IScheduledAction =
					scheduler.schedule(function():void { obs.onCompleted(); });
				
				return new ClosureSubscription(function():void
				{
					valueScheduledAction.cancel();
					completeScheduledAction.cancel();
				});
			});
		}
		
		public static function returnValue(type : Class, value : Object, scheduler : IScheduler = null) : IObservable
		{
			return returnValues(type, [value], scheduler); 
		}
		
		public static function catchErrors(sources : Array, scheduler : IScheduler = null) : IObservable
		{
			if (sources == null || sources.length == 0)
			{
				throw new ArgumentError("sources");
			}
			
			scheduler = resolveScheduler(scheduler);
			
			// Make internally immutable
			sources = new Array().concat(sources);
			
			return new ClosureObservable(sources[0].type, function(obs:IObserver) : ISubscription
			{
				var remainingSources : Array = new Array().concat(sources);
				
				var subscription : ISubscription = null;
				var scheduledAction : IScheduledAction = null;
				
				var moveNextFunc : Function = null;
				
				moveNextFunc = function():void
				{
					var currentSource : IObservable = remainingSources.shift();
						
					subscription = currentSource.subscribeFunc(
						function(pl:Object) : void { obs.onNext(pl); },
						function() : void { obs.onCompleted(); },
						function(e:Error) : void
						{
							if (remainingSources.length > 0)
							{
								scheduledAction = scheduler.schedule(moveNextFunc);
							}
							else
							{
								obs.onError(e);
							}
						});
				};
				
				scheduledAction = scheduler.schedule(moveNextFunc);
				
				return new ClosureSubscription(function():void
				{
					if (scheduledAction != null)
					{
						scheduledAction.cancel();
					}
					
					if (subscription != null)
					{
						subscription.unsubscribe();
					}
				});
			});
		}
		
		public static function resolveScheduler(scheduler : IScheduler) : IScheduler
		{
			return scheduler || Scheduler.defaultScheduler;
		}
		
		
		public static function merge(type : Class, source : IObservable, scheduler : IScheduler = null) : IObservable
		{
			if (source.type != IObservable)
			{
				throw new ArgumentError("merge can only merge an IObservable of IObservables");
			}
			
			scheduler = resolveScheduler(scheduler);
			
			return new ClosureObservable(type, function(obs:IObserver) : ISubscription
			{
				var subscription : CompositeSubscription = new CompositeSubscription([]);
				
				var sourceComplete : Boolean = false;
				
				subscription.add(source.subscribeFunc(
					function(innerSource:IObservable) : void
					{
						if (innerSource == null)
						{
							throw new IllegalOperationError("Cannot merge null IObservable");
						}
						
						var innerSubscription : FutureSubscription = new FutureSubscription();
						subscription.add(innerSubscription);
						
						innerSubscription.innerSubscription = innerSource.subscribeFunc(
							function(pl:Object) : void
							{
								obs.onNext(pl);
							},
							function() : void
							{
								innerSubscription.unsubscribe();
								subscription.remove(innerSubscription);
								
								if (sourceComplete && subscription.count == 1)
								{
									obs.onCompleted();
								}
							},
							function(e:Error) : void { obs.onError(e); }
						);
					},
					function() : void
					{
						sourceComplete = true;
						
						if (subscription.count == 1)
						{
							obs.onCompleted();
						}
					},
					function(e:Error) : void { obs.onError(e); }
					));
				
				return subscription;
			});
		}
	}
}
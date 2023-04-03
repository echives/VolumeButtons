# VolumeButtons

VolumeButtons is simple way to handling clicks on hardware volume buttons on iPhone or iPad. 

## Usage

```swift
volumeButtonHandler = VolumeButtonHandler(containerView: contentView)
// custom precondition logic, for example ensure ViewController is top and visible
volumeButtonHandler?.checkPreconditions = { [weak self] in
	guard let self = self else { return false }
	let isTopNavigation = (self.navigationController?.topViewController == self)
	let isTopPresent = (self.presentedViewController == nil)
	return isTopNavigation && isTopPresent && self.isVisiable
}
volumeButtonHandler?.buttonClosure = { [weak self] in
	self?.takePhoto()
}
```

## How it works

VolumeButtonHandler class keeps track of volume changes in an audio session. When you increase or decrease the volume level, the value will be reset to the initial one, thus pressing the buttons is determined without changing the volume of the media player. You need to pass in `init` some view of your View Controller for placing hidden instance `MPVolumeView` used for controlling volume level.

## Requirements

- iOS 11 and newer.
- RxSwift

## References

forked from [RedMadRobot/VolumeButtons](https://github.com/RedMadRobot/VolumeButtons)
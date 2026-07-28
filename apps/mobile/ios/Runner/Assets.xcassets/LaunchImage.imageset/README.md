# Изображение запуска iOS

Каталог содержит изображения, используемые `LaunchScreen.storyboard` при
старте iOS-приложения.

При замене ресурсов необходимо:

1. сохранить имена `LaunchImage.png`, `LaunchImage@2x.png` и
   `LaunchImage@3x.png`;
2. проверить соответствие scale в `Contents.json`;
3. открыть `ios/Runner.xcworkspace` в Xcode и проверить launch screen на
   нескольких размерах устройства;
4. не добавлять в изображение динамический текст, который может отличаться от
   первого Flutter frame.

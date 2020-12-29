# Asynchronous-Download

## Background

Applications often display a large number of images from the server accessible by url. To display them, you need to pre-load them, as well as cache them to avoid re-loading.

## Source data

The app contains a single screen with a table, the table displays a list of images and their urls. ImageDownloader is available in each cell. And with its help, images are loaded.

## Implementation 
'ImageDownloader' loads images from a link. Already downloaded images are cached in RAM and on disk. Each image is processed in a separate thread. GCD is used for implementation. If the image is requested again, another request to the network is not created.

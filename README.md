## Alice-In is a visual language for seeing data

People use apps to manage & consume data. Normally there's a database behind apps with tables and data. People use the apps to consume this data. However, the UI used by apps today uses textual representation, meaning apps use text to convey data. If the app has thousands of data items, it will represent those items in rows in a table or boxes with text. The main problem with textual representation is number of items a user can consume per minute is very low, leading to inability to consume a lot of data, & therefore inability to discover valuable data you weren't looking for. 

In the real world, e.g., when walking into a store or a crowded street, we use vision & are able to "consume" hundreds or thousands of items in seconds. Alice-in is a visual language for conveying the data in apps. It's a visual language meaning it allows people to see the data. When we talk about data visualization, we normally talk about data summary visualization - charts today only show a summary of the data across few dimensions. Alice-in tries to do full data visualization, meaning that you see all of your data with all of its dimensions, in a meaningful way.

To do that, Alice-in **embodies** data items in a way that reflects all of their dimensions & **embeds** items in a way that conveys their meaning. Here's a quick [demo using the Titanic dataset](https://www.youtube.com/watch?v=sUbdJN_OJpI).


<img width="1512" alt="Screenshot 2025-02-19 at 8 34 16 AM" src="https://github.com/user-attachments/assets/618691ff-e74b-4890-b084-b913969b1e55" />


## Simple-bldg-server

This repo is the reference-implementation of the Alice-in protocol server, that serves the Alice-in visualization to Alice-in [clients](https://github.com/AliceAlifib/alicein-bldg-client), & allows for users to Alice-into the visualizations & explore the data. It also works with Alice-in batteries that sync data with external data-sources.

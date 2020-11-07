//
//  command-channel.h
//  Runner
//

#ifndef COMMAND_CHANNEL_H
#define COMMAND_CHANNEL_H

class CommandQueue;

class CommandChannel
{
    CommandChannel();

public:
    static CommandChannel *getInstance();
    static void release();

    virtual ~CommandChannel();

    bool pushCommand(const char *cmd);
    bool popupCommand(char *buffer);
    bool pushResponse(const char *resp);
    bool popupResponse(char *buffer);

private:
    static CommandChannel *instance;

    CommandQueue *commandQueue;
    CommandQueue *responseQueue;
};

#endif /* COMMAND_CHANNEL_H */
